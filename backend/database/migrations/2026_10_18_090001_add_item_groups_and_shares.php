<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('notes', function (Blueprint $table) {
            $table->string('group_name', 80)->nullable()->after('title');
        });

        Schema::table('todos', function (Blueprint $table) {
            $table->string('group_name', 80)->nullable()->after('title');
        });

        Schema::create('item_shares', function (Blueprint $table) {
            $table->id();
            $table->string('item_type', 8);
            $table->unsignedBigInteger('item_id');
            $table->foreignId('owner_user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('shared_with_user_id')->constrained('users')->cascadeOnDelete();
            $table->timestamp('revoked_at')->nullable();
            $table->timestamps();
            $table->unique(['item_type', 'item_id', 'shared_with_user_id'], 'item_shares_target_unique');
            $table->index(['shared_with_user_id', 'revoked_at'], 'item_shares_incoming_index');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('item_shares');
        Schema::table('notes', fn (Blueprint $table) => $table->dropColumn('group_name'));
        Schema::table('todos', fn (Blueprint $table) => $table->dropColumn('group_name'));
    }
};
