# frozen_string_literal: true

require 'socket'
require 'json'
require 'net/http'
require 'uri'
require 'optparse'

#---------- 1️⃣  Récupération du channel ----------
options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby #{__FILE__} --channel CHANNEL"

  opts.on("--channel CHANNEL", "Nom du channel (sans le #) – obligatoire") do |v|
    options[:channel] = v
  end

  opts.on("-h", "--help", "Affiche cette aide") do
    puts opts
    exit
  end
end.parse!

# Vérification obligatoire
unless options[:channel]
  abort "Erreur : l’option --channel est requise.\nUtilisez -h pour afficher l’aide."
end

# ------------------- Config -------------------
BOT_NAME   = ''          # ton compte Twitch (celui qui peut lancer la commande)
CHANNEL    = options[:channel]                       # chaîne du stream
CLIENT_ID  = ''      # ID de l’application Twitch
BOT_OAUTH = 'oauth:' # token d’accès (scope clips:edit)

IRC_SERVER = 'irc.chat.twitch.tv'
IRC_PORT   = 6667
# -------------------------------------------------

def fetch_user_id(username, token)
  uri = URI("https://api.twitch.tv/helix/users?login=#{username}")
  req = Net::HTTP::Get.new(uri)
  req['Client-Id'] = CLIENT_ID
  req['Authorization'] = "Bearer #{token.sub(/^oauth:/, '')}"
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
  JSON.parse(res.body)['data'][0]['id']
end

def create_clip(broadcaster_id, token)
  uri = URI('https://api.twitch.tv/helix/clips')
  req = Net::HTTP::Post.new(uri)
  req['Client-Id'] = CLIENT_ID
  req['Authorization'] = "Bearer #{token.sub(/^oauth:/, '')}"
  req.set_form_data('broadcaster_id' => broadcaster_id)

  resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
  data = JSON.parse(resp.body)
  clip_id = data['data'][0]['id']

  sleep 5

  info_uri = URI("https://api.twitch.tv/helix/clips?id=#{clip_id}")
  info_req = Net::HTTP::Get.new(info_uri)
  info_req['Client-Id'] = CLIENT_ID
  info_req['Authorization'] = "Bearer #{token.sub(/^oauth:/, '')}"
  info_resp = Net::HTTP.start(info_uri.hostname, info_uri.port, use_ssl: true) { |h| h.request(info_req) }
  info = JSON.parse(info_resp.body)

  info['data'][0]['url']
end

def irc_send(sock, msg)
  sock.puts(msg)
  sock.flush
  puts ">> #{msg}"
end

def parse_irc(line)
  if line =~ /^:(\w+)!\w+@\w+\.tmi\.twitch\.tv PRIVMSG #(\w+) :(.+)$/
    { user: Regexp.last_match(1), channel: Regexp.last_match(2), text: Regexp.last_match(3).strip }
  end
end

# ------------------- Main (auto‑reconnect) -------------------
MAX_RETRIES = 0   # 0 = unlimited
RETRY_DELAY = 5   # seconds between attempts

retries = 0

begin
  socket = TCPSocket.new(IRC_SERVER, IRC_PORT)

  # ---- Handshake ----------------------------------------------------
  irc_send(socket, "PASS #{BOT_OAUTH}")
  irc_send(socket, "NICK #{BOT_NAME}")
  irc_send(socket, "JOIN ##{CHANNEL}")

  # Wait for the 001 (welcome) message before proceeding
  until (line = socket.gets)&.include?(' 001 ')
    puts "<< #{line}"
    irc_send(socket, "PONG #{line.split.last}") if line.start_with?('PING')
  end

  broadcaster_id = fetch_user_id(CHANNEL, BOT_OAUTH)

  # ---- Main read loop ------------------------------------------------
  loop do
    ready = IO.select([socket])
    next unless ready

    line = socket.gets
    break unless line   # socket closed → trigger rescue

    line.strip!
    puts "<< #{line}"

    irc_send(socket, "PONG #{line.split.last}") if line.start_with?('PING')

    msg = parse_irc(line)
    next unless msg

    # ------------------- !tc command -------------------
    if msg[:text].start_with?('!tc') && msg[:user].downcase == BOT_NAME.downcase
      clip_url = create_clip(broadcaster_id, BOT_OAUTH)
      irc_send(socket, "PRIVMSG ##{CHANNEL} :@ Voici ton clip : #{clip_url}")

      after_cmd = msg[:text].sub('!tc', '').strip
      irc_send(socket, "PRIVMSG ##{CHANNEL} :#{after_cmd}") unless after_cmd.empty?
      next
    end

    # ------------------- !ping command -------------------
    if msg[:text].start_with?('!ping') && msg[:user].downcase == BOT_NAME.downcase
     # sleep 1
      irc_send(socket, "PRIVMSG ##{CHANNEL} :pongggg!!!!")

      after_cmd = msg[:text].sub('!ping', '').strip
      irc_send(socket, "PRIVMSG ##{CHANNEL} :#{after_cmd}") unless after_cmd.empty?
      next
    end

   # sleep 0.1
  end

# ----------------------------------------------------------------------
rescue Errno::ECONNRESET, Errno::ETIMEDOUT, IOError, SocketError => e
  puts "⚠️  IRC connection lost (#{e.class}): #{e.message}"
  socket.close rescue nil
  retries += 1
  if MAX_RETRIES.zero? || retries <= MAX_RETRIES
    puts "🔄  Re‑connecting in #{RETRY_DELAY}s (attempt #{retries}/#{MAX_RETRIES.zero? ? '∞' : MAX_RETRIES})…"
    sleep RETRY_DELAY
    retry
  else
    puts "❌  Max reconnection attempts reached. Exiting."
    exit 1
  end
end
