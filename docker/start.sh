#!/bin/bash

# Script de inicialização simplificado para o Render.
# Assume-se que TODAS as variáveis de ambiente necessárias (APP_KEY, DB_*, etc.)
# são definidas diretamente no painel de Environment do Render e estão acessíveis ao PHP.

echo "[start.sh] Iniciando script de inicialização..."

# Verificação opcional de variáveis de ambiente essenciais
echo "[start.sh] Verificando variáveis de ambiente essenciais..."
if [ -z "$APP_KEY" ]; then
  echo "[start.sh] ALERTA: A variável de ambiente APP_KEY não foi detectada."
  echo "[start.sh] Certifique-se de que APP_KEY está definida nas Environment Variables do Render."
fi
if [ -z "$DB_CONNECTION" ]; then
  echo "[start.sh] ALERTA: A variável de ambiente DB_CONNECTION não foi detectada."
  echo "[start.sh] Certifique-se de que as configurações de banco de dados (DB_CONNECTION, DB_HOST, etc.) estão definidas no Render."
fi

# Cria o diretório GeoIP se não existir. O download do arquivo GeoIP deve ser feito
# no Dockerfile ou como parte do buildCommand no render.yaml.
echo "[start.sh] Verificando diretório GeoIP..."
if [ ! -d "storage/app/geoip" ]; then
  echo "[start.sh] Diretório storage/app/geoip não encontrado. Criando..."
  mkdir -p storage/app/geoip
  if [ -d "storage/app/geoip" ]; then
    echo "[start.sh] Diretório storage/app/geoip criado com sucesso."
  else
    echo "[start.sh] ERRO: Falha ao criar o diretório storage/app/geoip."
  fi
else
  echo "[start.sh] Diretório storage/app/geoip já existe."
fi

# Migrações, otimizações (config:cache, route:cache, view:cache, event:cache), 
# e php artisan optimize são executados no 'buildCommand' definido no render.yaml.

echo "[start.sh] Configurando o Apache..."
APACHE_PORT=${PORT:-80} # Render define a variável PORT; 80 é um fallback.
echo "[start.sh] Apache será configurado para escutar na porta: $APACHE_PORT"

# Configura o VirtualHost do Apache para usar a porta correta.
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
echo "[start.sh] Arquivo de configuração do VirtualHost (/etc/apache2/sites-available/000-default.conf) atualizado."

# Garante que o Apache escute na porta correta, comentando outras portas se necessário.
if ! grep -q "Listen $APACHE_PORT" /etc/apache2/ports.conf; then
  echo "[start.sh] Atualizando /etc/apache2/ports.conf para Listen $APACHE_PORT..."
  # Comenta Listen 80 se não for a porta desejada
  if [ "$APACHE_PORT" != "80" ] && grep -q -E "^\s*Listen\s+80\b" /etc/apache2/ports.conf; then
    sed -i -E 's/^(\s*Listen\s+80\b)/#\1/' /etc/apache2/ports.conf
    echo "[start.sh] Listen 80 comentado em ports.conf."
  fi
  # Comenta Listen 443 se não for a porta desejada (improvável para este setup)
  if [ "$APACHE_PORT" != "443" ] && grep -q -E "^\s*Listen\s+443\b" /etc/apache2/ports.conf; then
    sed -i -E 's/^(\s*Listen\s+443\b)/#\1/' /etc/apache2/ports.conf
    echo "[start.sh] Listen 443 comentado em ports.conf."
  fi
  echo "Listen $APACHE_PORT" >> /etc/apache2/ports.conf
  echo "[start.sh] Adicionado Listen $APACHE_PORT em ports.conf."
else
  echo "[start.sh] Apache já está configurado para Listen $APACHE_PORT em ports.conf."
fi

echo "[start.sh] Iniciando Apache em primeiro plano na porta $APACHE_PORT..."
apache2-foreground 