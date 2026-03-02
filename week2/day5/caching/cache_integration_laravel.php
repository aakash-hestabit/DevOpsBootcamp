<?php
/**
 * Redis Cache Integration for Stack 2 (Laravel + MySQL)
 *
 * File: caching/cache_integration_laravel.php
 *
 * Install:
 *   cd stack2_laravel_mysql_api
 *   composer require predis/predis
 *
 * Configuration steps:
 *   1. Copy the .env settings below into .env.production
 *   2. Run: php artisan config:cache
 *   3. Restart Laravel instances: sudo systemctl restart laravel-app-{8000,8001,8002}
 *
 * Redis DB: 1 (Stack 2 dedicated)
 */

// ---------------------------------------------------------------------------
// .env.production settings 
// ---------------------------------------------------------------------------
//
// CACHE_DRIVER=redis
// SESSION_DRIVER=redis
// QUEUE_CONNECTION=redis
//
// REDIS_HOST=127.0.0.1
// REDIS_PASSWORD=DevOpsRedis@123
// REDIS_PORT=6379
// REDIS_DB=1
// REDIS_CACHE_DB=1
// REDIS_SESSION_DB=3
//

// ---------------------------------------------------------------------------
// config/database.php — Redis connection configuration
// ---------------------------------------------------------------------------
// Add or update in the 'redis' section:
//
// 'redis' => [
//     'client' => env('REDIS_CLIENT', 'predis'),
//
//     'default' => [
//         'host'     => env('REDIS_HOST', '127.0.0.1'),
//         'password' => env('REDIS_PASSWORD', 'DevOpsRedis@123'),
//         'port'     => env('REDIS_PORT', 6379),
//         'database' => env('REDIS_DB', 1),
//     ],
//
//     'cache' => [
//         'host'     => env('REDIS_HOST', '127.0.0.1'),
//         'password' => env('REDIS_PASSWORD', 'DevOpsRedis@123'),
//         'port'     => env('REDIS_PORT', 6379),
//         'database' => env('REDIS_CACHE_DB', 1),
//     ],
//
//     'session' => [
//         'host'     => env('REDIS_HOST', '127.0.0.1'),
//         'password' => env('REDIS_PASSWORD', 'DevOpsRedis@123'),
//         'port'     => env('REDIS_PORT', 6379),
//         'database' => env('REDIS_SESSION_DB', 3),
//     ],
// ],

// ---------------------------------------------------------------------------
// Controller example: caching Eloquent query results
// ---------------------------------------------------------------------------

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use App\Models\User;

class UserController extends Controller
{
    /**
     * List all users with Redis caching (TTL: 10 minutes).
     */
    public function index()
    {
        $users = Cache::remember('laravel:users:all', 600, function () {
            return User::all();
        });

        return response()->json([
            'status' => 'ok',
            'cached' => Cache::has('laravel:users:all'),
            'data'   => $users,
        ]);
    }

    /**
     * Show a single user with caching (TTL: 5 minutes).
     */
    public function show($id)
    {
        $user = Cache::remember("laravel:users:{$id}", 300, function () use ($id) {
            return User::findOrFail($id);
        });

        return response()->json(['status' => 'ok', 'data' => $user]);
    }

    /**
     * Create user and invalidate list cache.
     */
    public function store(Request $request)
    {
        $user = User::create($request->validated());

        // Invalidate caches
        Cache::forget('laravel:users:all');

        return response()->json(['status' => 'ok', 'data' => $user], 201);
    }

    /**
     * Update user and invalidate relevant caches.
     */
    public function update(Request $request, $id)
    {
        $user = User::findOrFail($id);
        $user->update($request->validated());

        Cache::forget("laravel:users:{$id}");
        Cache::forget('laravel:users:all');

        return response()->json(['status' => 'ok', 'data' => $user]);
    }

    /**
     * Delete user and invalidate caches.
     */
    public function destroy($id)
    {
        User::destroy($id);

        Cache::forget("laravel:users:{$id}");
        Cache::forget('laravel:users:all');

        return response()->json(['status' => 'ok']);
    }
}

// ---------------------------------------------------------------------------
// Middleware: HTTP cache headers for API responses
// ---------------------------------------------------------------------------
// Add to app/Http/Middleware/CacheResponse.php:
//
// namespace App\Http\Middleware;
//
// use Closure;
//
// class CacheResponse
// {
//     public function handle($request, Closure $next, $maxAge = 60)
//     {
//         $response = $next($request);
//
//         if ($request->isMethod('GET') && $response->isSuccessful()) {
//             $response->header('Cache-Control', "public, max-age={$maxAge}");
//             $response->header('ETag', md5($response->getContent()));
//         }
//
//         return $response;
//     }
// }
