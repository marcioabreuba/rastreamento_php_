FROM php:8.2-apache

# Diretório de trabalho
WORKDIR /var/www/html

# Instalar dependências
RUN apt-get update && apt-get install -y \
    git \
    curl \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    zip \
    unzip \
    libzip-dev \
    libicu-dev \
    netcat-openbsd \
    libpq-dev \
    && docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd zip intl pdo_pgsql pgsql \
    && pecl install redis \
    && docker-php-ext-enable redis

# Instalar e configurar o GeoIP
RUN apt-get install -y libmaxminddb-dev \
    && pecl install maxminddb \
    && docker-php-ext-enable maxminddb

# Configurar o Apache
RUN a2enmod rewrite
COPY docker/apache/000-default.conf /etc/apache2/sites-available/000-default.conf

# Corrigir a configuração da porta do Apache
RUN echo "Listen \${PORT:-80}" > /etc/apache2/ports.conf
RUN sed -i 's/<VirtualHost \*:80>/<VirtualHost *:${PORT:-80}>/g' /etc/apache2/sites-available/000-default.conf

# Instalar o Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Copiar os arquivos da aplicação
COPY . .

# Configurar permissões
RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

# Instalar dependências do Composer
RUN composer install --no-interaction --no-dev --optimize-autoloader

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
ENTRYPOINT ["/usr/local/bin/start.sh"] 