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

# Abordagem mais agressiva para migração de banco de dados no Render
if [ ! -z "$RENDER" ]; then
  echo "Realizando reset completo do banco de dados..."
  
  # Primeira tentativa: Tentar remover todas as tabelas manualmente usando SQL direto
  DB_CONN_STRING="pgsql:host=$DB_HOST;port=$DB_PORT;dbname=$DB_DATABASE;user=$DB_USERNAME;password=$DB_PASSWORD"
  
  echo "Dropando tabelas existentes..."
  # Script SQL para listar e dropar todas as tabelas
  DROP_TABLES_SQL="
  SELECT 'DROP TABLE IF EXISTS \"' || tablename || '\" CASCADE;' 
  FROM pg_tables 
  WHERE schemaname = 'public';"
  
  # Executar o SQL para gerar os comandos de drop
  DROP_COMMANDS=$(php -r "
  try {
      \$pdo = new PDO('$DB_CONN_STRING');
      \$stmt = \$pdo->query(\"$DROP_TABLES_SQL\");
      \$dropCommands = \$stmt->fetchAll(PDO::FETCH_COLUMN);
      foreach (\$dropCommands as \$cmd) {
          echo \$cmd . \"\n\";
          \$pdo->exec(\$cmd);
      }
      echo \"Tabelas removidas com sucesso.\n\";
  } catch (Exception \$e) {
      echo \"Erro ao dropar tabelas: \" . \$e->getMessage() . \"\n\";
  }
  ")
  
  echo "$DROP_COMMANDS"
  
  # Segunda tentativa: Usar comandos do Laravel
  echo "Tentando schema:drop..."
  php artisan db:wipe --force || true
  
  # Terceira tentativa: Tentar migrate:fresh e migrate regular
  echo "Executando migrações..."
  php artisan migrate:fresh --force || php artisan migrate --force
else
  # Em outros ambientes, executar normal
  echo "Executando migrações..."
  php artisan migrate --force
fi

# Otimizar a aplicação
echo "Otimizando a aplicação..."
php artisan optimize

# Criar configuração Apache dinamicamente para resolver problema de variável
echo "Configurando Apache com a porta correta..."
APACHE_PORT=${PORT:-80}
echo "Porta do Apache: $APACHE_PORT"

# Reescrever o arquivo VirtualHost para usar a porta correta
cat > /etc/apache2/sites-available/000-default.conf << EOF
<VirtualHost *:$APACHE_PORT>
    ServerName localhost
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html/public

    <Directory /var/www/html/public>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

# Atualizar o arquivo ports.conf também
echo "Listen $APACHE_PORT" > /etc/apache2/ports.conf

# Iniciar o Apache
echo "Iniciando Apache na porta: $APACHE_PORT"
apache2-foreground 