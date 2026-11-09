<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('item_shares', function (Blueprint $table) {
            $table->string('permission', 16)->default('editor')->after('shared_with_user_id');
        });
    }

    public function down(): void
    {
        Schema::table('item_shares', function (Blueprint $table) {
            $table->dropColumn('permission');
        });
    }
};
