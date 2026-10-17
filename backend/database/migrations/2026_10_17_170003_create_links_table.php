<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('links', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('uuid', 36);
            $table->enum('source_type', ['note', 'todo']);
            $table->string('source_uuid', 36);
            $table->enum('target_type', ['note', 'todo']);
            $table->string('target_uuid', 36);
            $table->string('label')->nullable();
            $table->timestamp('deleted_at')->nullable();
            $table->timestamp('synced_at')->nullable();
            $table->timestamps();
            $table->unique(['user_id', 'source_uuid', 'target_uuid']);
            $table->unique(['user_id', 'uuid']);
            $table->index(['user_id', 'target_uuid']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('links');
    }
};
