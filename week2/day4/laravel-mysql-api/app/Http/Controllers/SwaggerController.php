<?php

namespace App\Http\Controllers;

/**
 * @OA\OpenApi(
 *     info=@OA\Info(
 *         version="1.0.0",
 *         title="Laravel Task API Documentation",
 *         description="Complete REST API for task management with MySQL backend",
 *         contact=@OA\Contact(name="API Support"),
 *         license=@OA\License(name="MIT")
 *     ),
 *     servers={
 *         @OA\Server(url="http://localhost:8880", description="Development Server")
 *     },
 *     tags={
 *         @OA\Tag(name="Health", description="Health check endpoints"),
 *         @OA\Tag(name="Tasks", description="Task management endpoints")
 *     }
 * )
 */
class SwaggerController
{
    //
}
