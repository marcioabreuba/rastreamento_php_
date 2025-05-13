FROM php:8.2-apache

# Diretório de trabalho
WORKDIR /var/www/html

# Instalar dependências PHP
RUN apt-get update && apt-get install -y \
    gnupg \
    ca-certificates \
    curl \
    git \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libzip-dev \
    zip \
    unzip \
    libpq-dev \
    libicu-dev \
    netcat-openbsd \
    # Node.js e npm removidos, pois o arquivo GeoIP já está no projeto
    # # Instalar Node.js e npm (exemplo para Node.js 18.x)
    # && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    # && apt-get install -y nodejs \
    # Continuar com as extensões PHP
    && pecl install redis \
    && docker-php-ext-enable redis \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd \
    && docker-php-ext-install pdo pdo_mysql pdo_pgsql bcmath exif intl opcache zip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Instalar a extensão PHP maxminddb (ainda necessária para ler o arquivo .mmdb)
RUN apt-get update && apt-get install -y libmaxminddb-dev \
    && pecl install maxminddb \
    && docker-php-ext-enable maxminddb \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Configurar o Apache
RUN a2enmod rewrite
COPY docker/apache/000-default.conf /etc/apache2/sites-available/000-default.conf.template

# Instalar o Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Copiar os arquivos da aplicação (incluindo storage/app/geoip/GeoLite2-City.mmdb)
COPY . .

# Configurar permissões
# Importante: Executar após COPY . .
RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

# Instalar dependências do Composer
RUN composer install --no-interaction --no-plugins --no-scripts --no-dev --prefer-dist --optimize-autoloader

# Criar diretórios necessários e definir permissões
# storage/app/geoip já deve existir devido ao COPY . ., mas mkdir -p é seguro.
RUN mkdir -p storage/app/public \
    && mkdir -p storage/app/geoip \
    && mkdir -p storage/framework/cache/data \
    && mkdir -p storage/framework/sessions \
    && mkdir -p storage/framework/views \
    && mkdir -p storage/logs \
    && chmod -R 775 storage bootstrap/cache

# Link do storage (se ainda não for feito de outra forma)
# RUN php artisan storage:link # Geralmente não é recomendado no build; melhor fazer no startCommand se necessário

# Script de inicialização
COPY docker/start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# Porta
EXPOSE ${PORT:-80}

# Entrypoint
CMD ["/usr/local/bin/start.sh"] 