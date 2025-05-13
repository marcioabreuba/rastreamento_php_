#!/bin/bash

# Esperar pelo MySQL se estiver em ambiente não-Render
if [ -z "$RENDER" ] && [ ! -z "${DB_HOST}" ]; then
  echo "Esperando pelo MySQL..."
  while ! nc -z $DB_HOST $DB_PORT; do
    sleep 0.5
  done
  echo "MySQL disponível!"
fi

# Configurar o .env
if [ ! -f .env ]; then
  echo "Criando arquivo .env..."
  cp .env.example .env
fi

# Gerar chave se não existir
if grep -q "APP_KEY=base64:" .env; then
  php artisan key:generate --force
fi

# Configurar banco de dados para Render
if [ ! -z "$RENDER" ] && [ ! -z "$RENDER_DATABASE_URL" ]; then
  echo "Configurando banco de dados para Render..."
  # Extrair informações da URL do banco de dados
  DB_HOST=$(echo $RENDER_DATABASE_URL | awk -F[@//] '{print $4}')
  DB_PORT=$(echo $RENDER_DATABASE_URL | awk -F[:] '{print $4}' | awk -F[/] '{print $1}')
  DB_DATABASE=$(echo $RENDER_DATABASE_URL | awk -F[/] '{print $4}')
  DB_USERNAME=$(echo $RENDER_DATABASE_URL | awk -F[:@] '{print $2}')
  DB_PASSWORD=$(echo $RENDER_DATABASE_URL | awk -F[:@] '{print $3}')
  
  # Atualizar o .env
  sed -i "s/^DB_HOST=.*/DB_HOST=$DB_HOST/" .env
  sed -i "s/^DB_PORT=.*/DB_PORT=$DB_PORT/" .env
  sed -i "s/^DB_DATABASE=.*/DB_DATABASE=$DB_DATABASE/" .env
  sed -i "s/^DB_USERNAME=.*/DB_USERNAME=$DB_USERNAME/" .env
  sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" .env
fi

# Verificar se a pasta GeoIP existe e tem conteúdo
if [ ! -d "storage/app/geoip" ] || [ -z "$(ls -A storage/app/geoip)" ]; then
  echo "Base de dados GeoIP não encontrada. Por favor, faça o download manualmente."
  mkdir -p storage/app/geoip
fi

# Limpar cache
echo "Limpando cache..."
php artisan optimize:clear

# Executar migrações
echo "Executando migrações..."
php artisan migrate --force

# Otimizar a aplicação
echo "Otimizando a aplicação..."
php artisan optimize

# Iniciar o Apache
apache2-foreground 