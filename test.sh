if [[ $(helm status prometheus | grep STATUS | cut -d : -f 2-) = *deployed* ]]; then
  echo "Found a Tomcat!"
fi