#!/bin/bash

# Configurar o .env
if [ ! -f .env ]; then
  echo "Criando arquivo .env..."
  cp .env.example .env
fi

# Definir APP_KEY se não existir
echo "Verificando APP_KEY..."
if ! grep -q "APP_KEY=" .env || grep -q "APP_KEY=base64:" .env; then
  echo "Gerando nova APP_KEY..."
  php artisan key:generate --force
  # Verificar se a chave foi gerada
  if grep -q "APP_KEY=base64:" .env; then
    echo "APP_KEY gerada com sucesso!"
  else
    echo "Erro ao gerar APP_KEY, adicionando manualmente..."
    # Gerar uma chave aleatória e adicioná-la diretamente ao .env
    RANDOM_KEY=$(openssl rand -base64 32)
    sed -i "s/APP_KEY=.*/APP_KEY=base64:$RANDOM_KEY/" .env
    if [ $? -ne 0 ]; then
      echo "APP_KEY=base64:$RANDOM_KEY" >> .env
    fi
  fi
fi

# Esperar pelo MySQL se estiver em ambiente não-Render
if [ -z "$RENDER" ] && [ ! -z "${DB_HOST}" ]; then
  echo "Esperando pelo MySQL..."
  while ! nc -z $DB_HOST $DB_PORT; do
    sleep 0.5
  done
  echo "MySQL disponível!"
fi

# Configurar banco de dados para Render
if [ ! -z "$RENDER" ] && [ ! -z "$RENDER_DATABASE_URL" ]; then
  echo "Configurando banco de dados para Render (PostgreSQL)..."
  
  # Atualizar o .env para usar PostgreSQL
  sed -i "s/^DB_CONNECTION=.*/DB_CONNECTION=pgsql/" .env
  
  # Extrair informações da URL do banco de dados
  if [[ $RENDER_DATABASE_URL == postgres://* ]]; then
    # Formato: postgres://username:password@host:port/database
    DB_USERNAME=$(echo $RENDER_DATABASE_URL | sed -E 's/^postgres:\/\/([^:]+):.*/\1/')
    DB_PASSWORD=$(echo $RENDER_DATABASE_URL | sed -E 's/^postgres:\/\/[^:]+:([^@]+).*/\1/')
    DB_HOST=$(echo $RENDER_DATABASE_URL | sed -E 's/^postgres:\/\/[^@]+@([^:]+).*/\1/')
    DB_PORT=$(echo $RENDER_DATABASE_URL | sed -E 's/^postgres:\/\/[^:]+:[^@]+@[^:]+:([0-9]+).*/\1/')
    DB_DATABASE=$(echo $RENDER_DATABASE_URL | sed -E 's/^postgres:\/\/[^\/]+\/([^?]+).*/\1/')
  else
    echo "Formato de URL de banco de dados não reconhecido. Usando valores padrão."
    DB_USERNAME=${DB_USERNAME:-postgres}
    DB_PASSWORD=${DB_PASSWORD:-postgres}
    DB_HOST=${DB_HOST:-localhost}
    DB_PORT=${DB_PORT:-5432}
    DB_DATABASE=${DB_DATABASE:-postgres}
  fi
  
  # Atualizar o .env
  sed -i "s/^DB_HOST=.*/DB_HOST=$DB_HOST/" .env
  sed -i "s/^DB_PORT=.*/DB_PORT=$DB_PORT/" .env
  sed -i "s/^DB_DATABASE=.*/DB_DATABASE=$DB_DATABASE/" .env
  sed -i "s/^DB_USERNAME=.*/DB_USERNAME=$DB_USERNAME/" .env
  sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" .env
  
  echo "Configuração do banco de dados concluída:"
  echo "  DB_CONNECTION: pgsql"
  echo "  DB_HOST: $DB_HOST"
  echo "  DB_PORT: $DB_PORT"
  echo "  DB_DATABASE: $DB_DATABASE"
  echo "  DB_USERNAME: $DB_USERNAME"
fi

# Verificar se a pasta GeoIP existe e tem conteúdo
if [ ! -d "storage/app/geoip" ] || [ -z "$(ls -A storage/app/geoip)" ]; then
  echo "Base de dados GeoIP não encontrada. Por favor, faça o download manualmente."
  mkdir -p storage/app/geoip
fi

# Limpar cache
echo "Limpando cache..."
php artisan optimize:clear

# Executar migrações com fresh para resolver problemas de transação
echo "Executando migrações com reset..."
if [ ! -z "$RENDER" ]; then
  # No ambiente Render, vamos tentar primeiro com --force para sobrescrever tabelas existentes
  php artisan migrate:fresh --force || php artisan migrate --force
else
  # Em outros ambientes, executar normal
  php artisan migrate --force
fi

# Otimizar a aplicação
echo "Otimizando a aplicação..."
php artisan optimize

# Iniciar o Apache com porta configurada pelo ambiente
echo "Iniciando Apache na porta: ${PORT:-80}"
apache2-foreground 