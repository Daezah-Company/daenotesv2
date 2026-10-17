<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('reminders', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('uuid', 36);
            $table->enum('item_type', ['note', 'todo']);
            $table->string('item_uuid', 36);
            $table->string('title');
            $table->timestamp('scheduled_at');
            $table->timestamp('fired_at')->nullable();
            $table->timestamp('deleted_at')->nullable();
            $table->timestamp('synced_at')->nullable();
            $table->timestamp('updated_at')->nullable();
            $table->unique(['user_id', 'uuid']);
            $table->index(['user_id', 'item_uuid']);
            $table->index(['user_id', 'scheduled_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('reminders');
    }
};
