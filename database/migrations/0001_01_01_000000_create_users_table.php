<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Log;

class CreateUsersTable extends Migration
{
    /**
     * Disable transaction for this migration to avoid abort on DDL.
     */
    public $withinTransaction = false;

    public function up()
    {
        // Table users
        if (! Schema::hasTable('users')) {
            Log::info('Criando tabela users...');
            Schema::create('users', function (Blueprint $table) {
                $table->id(); // Cria o campo 'id' como AUTO_INCREMENT e PRIMARY KEY
                $table->string('content_id')->nullable();
                $table->string('external_id')->unique(); // Cria 'external_id' como único
                $table->string('client_ip_address', 45)->nullable(); // 'client_ip_address' pode ser nulo
                $table->text('client_user_agent')->nullable(); // 'client_user_agent' pode ser nulo
                $table->string('fbp')->nullable(); // 'fbp' pode ser nulo
                $table->string('fbc')->nullable(); // 'fbc' pode ser nulo
                $table->string('country', 100)->nullable(); // 'country' pode ser nulo
                $table->string('st', 100)->nullable(); // 'st' pode ser nulo
                $table->string('ct', 100)->nullable(); // 'ct' pode ser nulo
                $table->string('zp', 10)->nullable(); // 'zp' pode ser nulo
                $table->string('fn')->nullable(); // 'fn' pode ser nulo
                $table->string('ln')->nullable(); // 'ln' pode ser nulo
                $table->string('em')->nullable(); // 'em' pode ser nulo
                $table->string('ph', 20)->nullable(); // 'ph' pode ser nulo
                $table->timestamps(0); // Cria 'created_at' e 'updated_at' com tipo TIMESTAMP
            });
            Log::info('Tabela users criada com sucesso');
        } else {
            Log::info('Tabela users já existe, pulando criação');
        }
    }

    public function down()
    {
        Schema::dropIfExists('users');
    }
}
