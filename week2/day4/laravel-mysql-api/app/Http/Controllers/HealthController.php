<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

/**
 * @OA\Info(title="Laravel Task API", version="1.0.0", description="Task management REST API with MySQL")
 * @OA\Server(url="http://localhost:8880", description="Development Server")
 */
class HealthController extends Controller
{
    /**
     * Health Check Endpoint
     * 
     * @OA\Get(
     *     path="/api/health",
     *     summary="Health Check",
     *     description="Returns application and database health status",
     *     tags={"Health"},
     *     @OA\Response(
     *         response=200,
     *         description="Application is healthy",
     *         @OA\JsonContent(
     *             @OA\Property(property="status", type="string", example="healthy"),
     *             @OA\Property(property="timestamp", type="string", format="date-time"),
     *             @OA\Property(property="uptime", type="integer"),
     *             @OA\Property(property="database", type="object",
     *                 @OA\Property(property="status", type="string", example="connected"),
     *                 @OA\Property(property="driver", type="string", example="mysql")
     *             ),
     *             @OA\Property(property="environment", type="string"),
     *             @OA\Property(property="version", type="string")
     *         )
     *     ),
     *     @OA\Response(response=503, description="Application is unhealthy")
     * )
     */
    public function __invoke(): JsonResponse
    {
        $dbStatus = 'disconnected';
        try {
            DB::connection()->getPdo();
            $dbStatus = 'connected';
        } catch (\Exception $e) {
            // DB unreachable — status stays disconnected
        }

        $healthy = $dbStatus === 'connected';

        return response()->json([
            'status'      => $healthy ? 'healthy' : 'unhealthy',
            'timestamp'   => now()->toIso8601String(),
            'uptime'      => (int) (microtime(true) - LARAVEL_START),
            'database'    => ['status' => $dbStatus, 'driver' => config('database.default')],
            'environment' => app()->environment(),
            'version'     => config('app.version', '1.0.0'),
        ], $healthy ? 200 : 503);
    }
}