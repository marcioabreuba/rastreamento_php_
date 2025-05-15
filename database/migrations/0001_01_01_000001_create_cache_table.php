<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Log;

return new class extends Migration
{
    /**
     * Disable transaction for this migration to avoid abort on DDL.
     */
    public $withinTransaction = false;

    /**
     * Run the migrations.
     */
    public function up(): void
    {
        // Table cache
        if (! Schema::hasTable('cache')) {
            Log::info('Criando tabela cache...');
            Schema::create('cache', function (Blueprint $table) {
                $table->string('key');
                $table->text('value');
                $table->integer('expiration');
                $table->primary('key');
            });
            Log::info('Tabela cache criada com sucesso');
        } else {
            Log::info('Tabela cache já existe, pulando criação');
        }

        // Table cache_locks
        if (! Schema::hasTable('cache_locks')) {
            Log::info('Criando tabela cache_locks...');
            Schema::create('cache_locks', function (Blueprint $table) {
                $table->string('key');
                $table->string('owner');
                $table->integer('expiration');
                $table->primary('key');
            });
            Log::info('Tabela cache_locks criada com sucesso');
        } else {
            Log::info('Tabela cache_locks já existe, pulando criação');
        }
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('cache');
        Schema::dropIfExists('cache_locks');
    }
};
