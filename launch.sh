#!/usr/bin/env bash
# run_two_channels.sh – lance deux instances du bot Ruby simultanément,
# chacune avec un channel différent.

source ~/.rvm/scripts/rvm

# Vérifier que le script Ruby existe
if [[ ! -f "main.rb" ]]; then
  echo "Erreur : main.rb introuvable dans le répertoire courant."
  exit 1
fi

# Première instance → channel NinhaYeslife
#ruby main.rb --channel NinhaYeslife &
#PID1=$!

# Deuxième instance → channel Akaruu
ruby main.rb --channel Akaruu #&
#PID2=$!

#echo "Instances démarrées : PID $PID1 (NinhaYeslife) et PID $PID2 (Akaruu)"

# Optionnel : attendre que les deux processus se terminent
#wait $PID1 $PID2
#echo "Les deux bots se sont terminés."
