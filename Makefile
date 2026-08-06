NAME = inception
COMPOSE = srcs/docker-compose.yml
DATA = /home/tfournie/data
SECRETS = secrets

all: up

secrets:
	@mkdir -p $(SECRETS)
	@test -f $(SECRETS)/db_password.txt      || openssl rand -hex 16 | tr -d '\n' > $(SECRETS)/db_password.txt
	@test -f $(SECRETS)/db_root_password.txt  || openssl rand -hex 16 | tr -d '\n' > $(SECRETS)/db_root_password.txt
	@test -f $(SECRETS)/wp_admin_password.txt || openssl rand -hex 16 | tr -d '\n' > $(SECRETS)/wp_admin_password.txt
	@test -f $(SECRETS)/wp_user_password.txt  || openssl rand -hex 16 | tr -d '\n' > $(SECRETS)/wp_user_password.txt
	@echo "secrets prets."

up: secrets
	mkdir -p $(DATA)/mariadb $(DATA)/wordpress
	docker compose -f $(COMPOSE) up -d --build

down:
	docker compose -f $(COMPOSE) down

clean: down
	docker system prune -af

fclean:
	docker compose -f $(COMPOSE) down -v
	docker run --rm -v $(DATA):/data alpine:3.23 rm -rf /data/mariadb /data/wordpress
	docker system prune -af

re: fclean up

.PHONY: all up down clean fclean re secrets