#!/usr/bin/env bash
#
# bash <(curl -s https://raw.githubusercontent.com/AndriyKalashnykov/sim/main/install.sh)
#

set -euo pipefail

read -rp "GitHub Username: " user
read -rp "Projectname: " projectname

git clone git@github.com:AndriyKalashnykov/go-kafka-confluent-examples.git "$projectname"
cd "$projectname"
rm -rf .git
find . -type f -exec sed -i "s/go-kafka-confluent-examples/$projectname/g" {} +
find . -type f -exec sed -i "s/[Aa]ndriy[Kk]alashnykov/$user/g" {} +
git init
git add .
git commit -m "initial commit"
git remote add origin "git@github.com:$user/$projectname.git"

echo "Template successfully installed."

exit 0
