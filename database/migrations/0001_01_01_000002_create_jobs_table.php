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
        // Table jobs
        if (! Schema::hasTable('jobs')) {
            Log::info('Criando tabela jobs...');
            Schema::create('jobs', function (Blueprint $table) {
                $table->id();
                $table->string('queue')->index();
                $table->longText('payload');
                $table->unsignedTinyInteger('attempts');
                $table->unsignedInteger('reserved_at')->nullable();
                $table->unsignedInteger('available_at');
                $table->unsignedInteger('created_at');
            });
            Log::info('Tabela jobs criada com sucesso');
        } else {
            Log::info('Tabela jobs já existe, pulando criação');
        }

        // Table job_batches
        if (! Schema::hasTable('job_batches')) {
            Log::info('Criando tabela job_batches...');
            Schema::create('job_batches', function (Blueprint $table) {
                $table->string('id')->primary();
                $table->string('name');
                $table->integer('total_jobs');
                $table->integer('pending_jobs');
                $table->integer('failed_jobs');
                $table->longText('failed_job_ids');
                $table->text('options')->nullable();
                $table->integer('cancelled_at')->nullable();
                $table->integer('created_at');
                $table->integer('finished_at')->nullable();
            });
            Log::info('Tabela job_batches criada com sucesso');
        } else {
            Log::info('Tabela job_batches já existe, pulando criação');
        }

        // Table failed_jobs
        if (! Schema::hasTable('failed_jobs')) {
            Log::info('Criando tabela failed_jobs...');
            Schema::create('failed_jobs', function (Blueprint $table) {
                $table->id();
                $table->string('uuid')->unique();
                $table->text('connection');
                $table->text('queue');
                $table->longText('payload');
                $table->longText('exception');
                $table->timestamp('failed_at')->useCurrent();
            });
            Log::info('Tabela failed_jobs criada com sucesso');
        } else {
            Log::info('Tabela failed_jobs já existe, pulando criação');
        }
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('jobs');
        Schema::dropIfExists('job_batches');
        Schema::dropIfExists('failed_jobs');
    }
};
