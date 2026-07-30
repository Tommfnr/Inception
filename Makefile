NAME = inception
COMPOSE = srcs/docker-compose.yml
DATA = /home/tfournie/data

all: up

# Cree les dossiers des volumes puis build+démarre
up:
	mkdir -p $(DATA)/mariadb $(DATA)/wordpress
	docker compose -f $(COMPOSE) up -d --build

down:
	docker compose -f $(COMPOSE) down

# Stop + suppression volumes + images (remise à zéro)
clean: down
	docker system prune -af

# Remise a zero totale : conteneurs + volumes + donnees + images
# Les donnees appartiennent a un UID interne au conteneur -> on les efface
# depuis un conteneur (marche en root comme en rootless, sans sudo)
fclean:
	docker compose -f $(COMPOSE) down -v
	docker run --rm -v $(DATA):/data alpine:3.23 rm -rf /data/mariadb /data/wordpress
	docker system prune -af

re: fclean up

.PHONY: all up down clean fclean re