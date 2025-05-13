#!/bin/bash

# Configurar o .env
if [ ! -f .env ]; then
  echo "Criando arquivo .env..."
  cp .env.example .env
fi

# Definir APP_KEY se não existir
echo "Verificando APP_KEY..."
# Verifica se APP_KEY está ausente, é a string padrão do Laravel, ou não parece uma chave base64 válida
if ! grep -q "APP_KEY=" .env || grep -q "APP_KEY=base64:\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\=" .env || ! grep -E "APP_KEY=base64:[a-zA-Z0-9+/]{42}[AEIMQUYcgkosw048]=?" .env; then
  echo "APP_KEY ausente ou inválida, gerando nova APP_KEY..."
  php artisan key:generate --force
  if grep -E "APP_KEY=base64:[a-zA-Z0-9+/]{42}[AEIMQUYcgkosw048]=?" .env; then
    echo "APP_KEY gerada com sucesso e é válida!"
  else
    echo "ERRO CRÍTICO: Falha ao gerar uma APP_KEY válida. Verifique as permissões ou o ambiente Laravel."
    exit 1 # Falhar o script se a APP_KEY não puder ser gerada
  fi
fi

# Esperar pelo MySQL se estiver em ambiente não-Render (mantido para flexibilidade)
if [ -z "$RENDER" ] && [ ! -z "${DB_HOST}" ]; then
  echo "Esperando pelo MySQL..."
  while ! nc -z $DB_HOST $DB_PORT; do
    sleep 0.5
  done
  echo "MySQL disponível!"
fi

# Configurar banco de dados para Render
if [ ! -z "$RENDER" ] && [ ! -z "$RENDER_DATABASE_URL" ]; then
  echo "Configurando banco de dados para Render (PostgreSQL) no .env..."
  
  sed -i "s|^DB_CONNECTION=.*|DB_CONNECTION=pgsql|" .env
  
  # Extração robusta dos componentes da URL do banco de dados PostgreSQL
  DB_USERNAME=$(echo $RENDER_DATABASE_URL | sed -n 's_postgres://\([^:]*\):.*_\1_p')
  DB_PASSWORD=$(echo $RENDER_DATABASE_URL | sed -n 's_postgres://[^:]*:\([^@]*\)@.*_\1_p')
  DB_HOST=$(echo $RENDER_DATABASE_URL | sed -n 's_postgres://[^@]*@\([^:]*\):.*_\1_p')
  DB_PORT=$(echo $RENDER_DATABASE_URL | sed -n 's_postgres://[^:]*:[^@]*@[^:]*:\([0-9]*\)/.*_\1_p')
  DB_DATABASE=$(echo $RENDER_DATABASE_URL | sed -n 's_postgres://[^/]*/\([^?]*\).*_\1_p')
  
  sed -i "s|^DB_HOST=.*|DB_HOST=$DB_HOST|" .env
  sed -i "s|^DB_PORT=.*|DB_PORT=$DB_PORT|" .env
  sed -i "s|^DB_DATABASE=.*|DB_DATABASE=$DB_DATABASE|" .env
  sed -i "s|^DB_USERNAME=.*|DB_USERNAME=$DB_USERNAME|" .env
  sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$DB_PASSWORD|" .env
  
  echo "Configuração do banco de dados no .env atualizada para Render."
  echo "  DB_HOST: $DB_HOST"
  echo "  DB_PORT: $DB_PORT"
  echo "  DB_DATABASE: $DB_DATABASE"
fi

# Verificar se a pasta GeoIP existe (Download/Criação deve ser no Dockerfile ou buildCommand)
if [ ! -d "storage/app/geoip" ] || [ -z "$(ls -A storage/app/geoip)" ]; then
  echo "AVISO: Base de dados GeoIP não encontrada em storage/app/geoip. Crie o diretório se necessário."
  mkdir -p storage/app/geoip
fi

# As migrações e otimizações (php artisan optimize, optimize:clear) 
# agora são tratadas no buildCommand do render.yaml.

# Criar configuração Apache dinamicamente para resolver problema de variável
echo "Configurando Apache com a porta correta..."
APACHE_PORT=${PORT:-80} # Render define PORT, 80 é fallback
echo "Porta do Apache: $APACHE_PORT"

# Reescrever o arquivo VirtualHost para usar a porta correta
cat > /etc/apache2/sites-available/000-default.conf << EOF
<VirtualHost *:$APACHE_PORT>
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

# Atualizar o arquivo ports.conf também, garantindo que não haja duplicatas
if ! grep -q "Listen $APACHE_PORT" /etc/apache2/ports.conf; then
  # Se a porta padrão 80 ou 443 estiver lá e for diferente da APACHE_PORT, comente-as
  if [ "$APACHE_PORT" != "80" ] && grep -q "Listen 80" /etc/apache2/ports.conf; then
    sed -i 's/^Listen 80/#Listen 80/' /etc/apache2/ports.conf
  fi
  if [ "$APACHE_PORT" != "443" ] && grep -q "Listen 443" /etc/apache2/ports.conf; then
    sed -i 's/^Listen 443/#Listen 443/' /etc/apache2/ports.conf
  fi
  echo "Listen $APACHE_PORT" >> /etc/apache2/ports.conf
fi

# Iniciar o Apache
echo "Iniciando Apache na porta: $APACHE_PORT"
apache2-foreground 