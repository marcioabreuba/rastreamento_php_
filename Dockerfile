FROM php:8.2-apache

# Diretório de trabalho
WORKDIR /var/www/html

# Instalar dependências
RUN apt-get update && apt-get install -y \
    gnupg \
    apt-transport-https \
    git \
    curl \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libzip-dev \
    zip \
    unzip \
    libpq-dev \
    libicu-dev \
    netcat-openbsd \
    # Adicionar o PPA da MaxMind e instalar geoipupdate
    && curl -fsSL https://ppa.launchpadcontent.net/maxmind/ppa/ubuntu/dists/jammy/Release.gpg | gpg --dearmor -o /usr/share/keyrings/maxmind-ppa-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/maxmind-ppa-archive-keyring.gpg] https://ppa.launchpadcontent.net/maxmind/ppa/ubuntu jammy main" > /etc/apt/sources.list.d/maxmind-ppa.list \
    && apt-get update && apt-get install -y geoipupdate \
    # Continuar com as extensões PHP
    && pecl install redis \
    && docker-php-ext-enable redis \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd \
    && docker-php-ext-install pdo pdo_mysql pdo_pgsql bcmath exif intl opcache zip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Instalar e configurar o GeoIP (extensão PHP maxminddb) - esta parte é para a extensão PHP, não o geoipupdate em si
# A instalação do geoipupdate acima já cuida de obter o programa para atualizar o banco de dados.
# RUN apt-get update && apt-get install -y libmaxminddb-dev \
#     && (pecl install -f -n maxminddb || true) \
#     && docker-php-ext-enable maxminddb || true
# Mantendo a instalação da extensão PHP maxminddb, pois é necessária para ler o arquivo .mmdb
RUN apt-get update && apt-get install -y libmaxminddb-dev \
    && pecl install maxminddb \
    && docker-php-ext-enable maxminddb \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Configurar o Apache
RUN a2enmod rewrite
COPY docker/apache/000-default.conf /etc/apache2/sites-available/000-default.conf.template

# Instalar o Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Copiar os arquivos da aplicação
COPY composer.json composer.lock ./
COPY . .

# Configurar permissões
RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

# Instalar dependências do Composer
RUN composer install --no-interaction --no-plugins --no-scripts --no-dev --prefer-dist --optimize-autoloader

# Criar diretórios necessários
RUN mkdir -p storage/app/geoip \
    && mkdir -p storage/framework/cache \
    && mkdir -p storage/framework/sessions \
    && mkdir -p storage/framework/views \
    && mkdir -p storage/logs \
    && chmod -R 775 storage bootstrap/cache

# Script de inicialização
COPY docker/start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# Porta (será substituída pela variável PORT no Render)
EXPOSE ${PORT:-80}

# Entrypoint
CMD ["/usr/local/bin/start.sh"] 