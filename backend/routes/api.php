<?php

use App\Http\Controllers\AuthController;
use App\Http\Controllers\CollaborationController;
use App\Http\Controllers\GraphController;
use App\Http\Controllers\LinkController;
use App\Http\Controllers\NoteController;
use App\Http\Controllers\ReminderController;
use App\Http\Controllers\SyncController;
use App\Http\Controllers\TodoController;
use Illuminate\Support\Facades\Route;

Route::prefix('auth')->group(function () {
    Route::post('register', [AuthController::class, 'register']);
    Route::post('login', [AuthController::class, 'login']);

    Route::middleware('auth:sanctum')->group(function () {
        Route::post('logout', [AuthController::class, 'logout']);
        Route::get('me', [AuthController::class, 'me']);
    });
});

Route::middleware('auth:sanctum')->group(function () {
    Route::get('collaboration/{type}/{uuid}', [CollaborationController::class, 'index'])
        ->where(['type' => 'note|todo', 'uuid' => '[A-Za-z0-9-]+']);
    Route::post('collaboration/{type}/{uuid}', [CollaborationController::class, 'store'])
        ->where(['type' => 'note|todo', 'uuid' => '[A-Za-z0-9-]+']);
    Route::put('collaboration/{type}/{uuid}/{userId}', [CollaborationController::class, 'update'])
        ->where(['type' => 'note|todo', 'uuid' => '[A-Za-z0-9-]+', 'userId' => '[0-9]+']);
    Route::delete('collaboration/{type}/{uuid}/{userId}', [CollaborationController::class, 'destroy'])
        ->where(['type' => 'note|todo', 'uuid' => '[A-Za-z0-9-]+', 'userId' => '[0-9]+']);

    Route::get('notes', [NoteController::class, 'index']);
    Route::post('notes', [NoteController::class, 'store']);
    Route::get('notes/{uuid}', [NoteController::class, 'show'])->where('uuid', '[A-Za-z0-9-]+');
    Route::put('notes/{uuid}', [NoteController::class, 'update'])->where('uuid', '[A-Za-z0-9-]+');
    Route::delete('notes/{uuid}', [NoteController::class, 'destroy'])->where('uuid', '[A-Za-z0-9-]+');
    Route::post('notes/{uuid}/archive', [NoteController::class, 'archive']);
    Route::post('notes/{uuid}/restore', [NoteController::class, 'restore']);

    Route::get('todos', [TodoController::class, 'index']);
    Route::post('todos', [TodoController::class, 'store']);
    Route::put('todos/{uuid}', [TodoController::class, 'update'])->where('uuid', '[A-Za-z0-9-]+');
    Route::patch('todos/{uuid}/toggle', [TodoController::class, 'toggle']);
    Route::delete('todos/{uuid}', [TodoController::class, 'destroy'])->where('uuid', '[A-Za-z0-9-]+');

    Route::get('links', [LinkController::class, 'index']);
    Route::post('links', [LinkController::class, 'store']);
    Route::delete('links/{uuid}', [LinkController::class, 'destroy'])->where('uuid', '[A-Za-z0-9-]+');

    Route::get('graph', [GraphController::class, 'index']);

    Route::get('sync/changes', [SyncController::class, 'changes']);
    Route::post('sync/push', [SyncController::class, 'push']);

    Route::get('reminders', [ReminderController::class, 'index']);
    Route::post('reminders', [ReminderController::class, 'store']);
    Route::patch('reminders/{uuid}/fire', [ReminderController::class, 'fire']);
});
