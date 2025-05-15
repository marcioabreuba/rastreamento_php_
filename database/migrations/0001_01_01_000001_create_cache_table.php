<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Log;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Log::info('Iniciando migração da tabela cache');
        try {
            Schema::create('cache', function (Blueprint $table) {
                $table->string('key')->primary();
                $table->text('value');
                $table->integer('expiration');
            });
            Log::info('Tabela cache criada com sucesso');

            Schema::create('cache_locks', function (Blueprint $table) {
                $table->string('key')->primary();
                $table->string('owner');
                $table->integer('expiration');
            });
        } catch (\Exception $e) {
            Log::error('Falha ao criar tabela cache: '.$e->getMessage());
            throw $e;
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
