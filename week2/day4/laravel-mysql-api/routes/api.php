<?php

use App\Http\Controllers\HealthController;
use App\Http\Controllers\TaskController;
use Illuminate\Support\Facades\Route;

/*
 API Routes
 All routes are prefixed with /api by the RouteServiceProvider.
*/

Route::get('/health', HealthController::class);

Route::apiResource('tasks', TaskController::class);
Route::post('tasks/{task}/complete', [TaskController::class, 'complete'])
    ->name('tasks.complete');