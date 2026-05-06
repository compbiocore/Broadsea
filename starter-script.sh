# Git clones in the beginning 
#git clone https://github.com/OHDSI/Broadsea.git
#cd Broadsea

# start stack with default profile 
docker compose --profile default up -d

# launch pgAdmin
docker compose --profile pgadmin4 up -d

# Open Shiny Server
docker compose --profile open-shiny-server up -d

# Ares (requires small fix noted below)
docker compose build broadsea-ares
docker compose --profile ares up -d

# ---- Download Ares files from git 
#git clone https://github.com/OHDSI/Ares.git

# Modify Dockerfile there by adding NODE_OPTIONS=--max-old-space-size=4096 (increase memory for JS)

# Go back to docker-compose.yml in Broadsea and change: 
# broadsea-ares:
#   build:
#    context: https://github.com/OHDSI/Ares.git
# To use local cloned ./Ares repo with increased memory for JS so npm run doesn't fail

# When finished, go to http://127.0.0.1 and you should see stack 