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
  echo "Realizando reset completo do banco de dados PostgreSQL..."
  
  # Configurar strings de conexão
  DB_CONN_STRING="pgsql:host=$DB_HOST;port=$DB_PORT;dbname=$DB_DATABASE;user=$DB_USERNAME;password=$DB_PASSWORD"
  
  # Limpeza completa do PostgreSQL em três camadas
  echo "===== INICIANDO LIMPEZA COMPLETA DO BANCO DE DADOS ====="
  
  # CAMADA 1: Terminar todas as conexões existentes e limpar completamente o schema
  echo "CAMADA 1: Terminando conexões existentes e limpando schema..."
  
  php -r "
  try {
      echo \"Conectando ao PostgreSQL...\n\";
      \$pdo = new PDO('$DB_CONN_STRING');
      \$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
      
      echo \"Terminando conexões existentes...\n\";
      // Primeiro, cancelar qualquer consulta em execução que não seja a nossa
      \$sql = \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity 
              WHERE pid <> pg_backend_pid() 
              AND datname = '$DB_DATABASE';\";
      \$stmt = \$pdo->prepare(\$sql);
      \$stmt->execute();
      echo \"Conexões terminadas.\n\";
      
      echo \"Recriando schema público...\n\";
      // Dropar e recriar o schema público
      \$pdo->exec('DROP SCHEMA IF EXISTS public CASCADE;');
      \$pdo->exec('CREATE SCHEMA public;');
      
      // Dar as permissões necessárias
      \$pdo->exec('GRANT ALL ON SCHEMA public TO public;');
      \$pdo->exec('GRANT ALL ON SCHEMA public TO \"$DB_USERNAME\";');
      
      echo \"Schema público recriado com sucesso.\n\";
  } catch (PDOException \$e) {
      echo \"Erro na CAMADA 1: \" . \$e->getMessage() . \"\n\";
  }
  "
  
  # CAMADA 2: Usar comandos Laravel para limpar o banco de dados
  echo "CAMADA 2: Utilizando comandos Laravel para limpar o banco de dados..."
  php artisan db:wipe --force || true
  
  # CAMADA 3: Forçar o DROP de objetos individuais
  echo "CAMADA 3: Forçando remoção de objetos individuais..."
  
  php -r "
  try {
      \$pdo = new PDO('$DB_CONN_STRING');
      \$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
      
      // Lista todas as tabelas
      \$sql = \"SELECT tablename FROM pg_tables WHERE schemaname = 'public';\";
      \$stmt = \$pdo->query(\$sql);
      \$tables = \$stmt->fetchAll(PDO::FETCH_COLUMN);
      
      if (count(\$tables) > 0) {
          echo \"Removendo \" . count(\$tables) . \" tabelas restantes...\n\";
          foreach (\$tables as \$table) {
              \$dropSql = \"DROP TABLE IF EXISTS \\\"\$table\\\" CASCADE;\";
              echo \"Executando: \$dropSql\n\";
              \$pdo->exec(\$dropSql);
          }
      } else {
          echo \"Nenhuma tabela encontrada para remover.\n\";
      }
      
      // Lista todas as sequências
      \$sql = \"SELECT sequencename FROM pg_sequences WHERE schemaname = 'public';\";
      \$stmt = \$pdo->query(\$sql);
      \$sequences = \$stmt->fetchAll(PDO::FETCH_COLUMN);
      
      if (count(\$sequences) > 0) {
          echo \"Removendo \" . count(\$sequences) . \" sequências restantes...\n\";
          foreach (\$sequences as \$sequence) {
              \$dropSql = \"DROP SEQUENCE IF EXISTS \\\"\$sequence\\\" CASCADE;\";
              echo \"Executando: \$dropSql\n\";
              \$pdo->exec(\$dropSql);
          }
      } else {
          echo \"Nenhuma sequência encontrada para remover.\n\";
      }
      
      echo \"Limpeza de objetos individuais concluída.\n\";
  } catch (PDOException \$e) {
      echo \"Erro na CAMADA 3: \" . \$e->getMessage() . \"\n\";
  }
  "
  
  echo "===== LIMPEZA COMPLETA FINALIZADA ====="
  
  # Executar migrações com maior robustez
  echo "Executando migrações com tratamento aprimorado..."
  
  # Primeiro tentar migrate:fresh (que deve funcionar agora com o banco limpo)
  echo "Tentativa 1: migrate:fresh"
  if php artisan migrate:fresh --force; then
      echo "Migrações executadas com sucesso via migrate:fresh!"
  else
      echo "Falha no migrate:fresh, tentando migrate padrão..."
      
      # Se falhar, tentar migrate normal
      echo "Tentativa 2: migrate padrão"
      if php artisan migrate --force; then
          echo "Migrações executadas com sucesso via migrate padrão!"
      else
          echo "ERRO: Todas as tentativas de migração falharam."
          echo "Verificando estado do banco de dados após falhas..."
          
          # Diagnóstico final
          php -r "
          try {
              \$pdo = new PDO('$DB_CONN_STRING');
              \$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
              
              echo \"Tabelas existentes no banco de dados:\n\";
              \$stmt = \$pdo->query(\"SELECT tablename FROM pg_tables WHERE schemaname = 'public';\");
              \$tables = \$stmt->fetchAll(PDO::FETCH_COLUMN);
              
              if (count(\$tables) > 0) {
                  foreach (\$tables as \$table) {
                      echo \" - \$table\n\";
                  }
              } else {
                  echo \" * Nenhuma tabela encontrada\n\";
              }
              
              echo \"Status das migrations:\n\";
              if (in_array('migrations', \$tables)) {
                  \$stmt = \$pdo->query(\"SELECT migration, batch FROM migrations ORDER BY batch, migration;\");
                  \$migrations = \$stmt->fetchAll(PDO::FETCH_ASSOC);
                  
                  if (count(\$migrations) > 0) {
                      foreach (\$migrations as \$migration) {
                          echo \" - {\$migration['migration']} (Batch: {\$migration['batch']})\n\";
                      }
                  } else {
                      echo \" * Tabela migrations existe mas está vazia\n\";
                  }
              } else {
                  echo \" * Tabela migrations não existe\n\";
              }
          } catch (PDOException \$e) {
              echo \"Erro durante diagnóstico: \" . \$e->getMessage() . \"\n\";
          }
          "
      fi
  fi
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