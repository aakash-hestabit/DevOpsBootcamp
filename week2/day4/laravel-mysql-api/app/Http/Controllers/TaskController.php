<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreTaskRequest;
use App\Http\Requests\UpdateTaskRequest;
use App\Models\Task;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

/**
 * @OA\Schema(
 *     schema="Task",
 *     type="object",
 *     @OA\Property(property="id", type="integer", example=1),
 *     @OA\Property(property="title", type="string", example="Set up CI/CD pipeline"),
 *     @OA\Property(property="description", type="string", example="Configure GitHub Actions"),
 *     @OA\Property(property="status", type="string", enum={"pending","in_progress","completed"}),
 *     @OA\Property(property="priority", type="string", enum={"low","medium","high"}),
 *     @OA\Property(property="due_date", type="string", format="date-time", nullable=true),
 *     @OA\Property(property="created_at", type="string", format="date-time"),
 *     @OA\Property(property="updated_at", type="string", format="date-time")
 * )
 * @OA\Schema(
 *     schema="TaskResponse",
 *     type="object",
 *     @OA\Property(property="status", type="string"),
 *     @OA\Property(property="data", ref="#/components/schemas/Task")
 * )
 * @OA\Schema(
 *     schema="TaskListResponse",
 *     type="object",
 *     @OA\Property(property="status", type="string"),
 *     @OA\Property(property="data", type="array", @OA\Items(ref="#/components/schemas/Task")),
 *     @OA\Property(property="meta", type="object",
 *         @OA\Property(property="total", type="integer"),
 *         @OA\Property(property="per_page", type="integer"),
 *         @OA\Property(property="current_page", type="integer"),
 *         @OA\Property(property="last_page", type="integer")
 *     )
 * )
 */
class TaskController extends Controller
{
    /**
     * List Tasks
     * 
     * @OA\Get(
     *     path="/api/tasks",
     *     summary="List all tasks",
     *     description="Get a paginated list of tasks with optional filtering",
     *     tags={"Tasks"},
     *     @OA\Parameter(
     *         name="page",
     *         in="query",
     *         description="Page number",
     *         required=false,
     *         @OA\Schema(type="integer", default=1)
     *     ),
     *     @OA\Parameter(
     *         name="per_page",
     *         in="query",
     *         description="Items per page",
     *         required=false,
     *         @OA\Schema(type="integer", default=15)
     *     ),
     *     @OA\Parameter(
     *         name="status",
     *         in="query",
     *         description="Filter by status",
     *         required=false,
     *         @OA\Schema(type="string", enum={"pending","in_progress","completed"})
     *     ),
     *     @OA\Parameter(
     *         name="priority",
     *         in="query",
     *         description="Filter by priority",
     *         required=false,
     *         @OA\Schema(type="string", enum={"low","medium","high"})
     *     ),
     *     @OA\Response(response=200, description="Success", @OA\JsonContent(ref="#/components/schemas/TaskListResponse"))
     * )
     */
    public function index(Request $request): JsonResponse
    {
        $query = Task::query()->orderBy('created_at', 'desc');

        if ($request->has('status')) {
            $query->status($request->status);
        }
        if ($request->has('priority')) {
            $query->priority($request->priority);
        }

        $tasks = $query->paginate($request->integer('per_page', 15));

        return response()->json([
            'status' => 'success',
            'data'   => $tasks->items(),
            'meta'   => [
                'total'        => $tasks->total(),
                'per_page'     => $tasks->perPage(),
                'current_page' => $tasks->currentPage(),
                'last_page'    => $tasks->lastPage(),
            ],
        ]);
    }

    /**
     * Get Single Task
     * 
     * @OA\Get(
     *     path="/api/tasks/{id}",
     *     summary="Get a task",
     *     description="Retrieve a single task by ID",
     *     tags={"Tasks"},
     *     @OA\Parameter(name="id", in="path", required=true, description="Task ID", @OA\Schema(type="integer")),
     *     @OA\Response(response=200, description="Success", @OA\JsonContent(ref="#/components/schemas/TaskResponse")),
     *     @OA\Response(response=404, description="Task not found")
     * )
     */
    public function show(Task $task): JsonResponse
    {
        return response()->json(['status' => 'success', 'data' => $task]);
    }

    /**
     * Create Task
     * 
     * @OA\Post(
     *     path="/api/tasks",
     *     summary="Create a task",
     *     description="Create a new task",
     *     tags={"Tasks"},
     *     @OA\RequestBody(
     *         required=true,
     *         @OA\JsonContent(
     *             required={"title","status","priority"},
     *             @OA\Property(property="title", type="string", example="New Task"),
     *             @OA\Property(property="description", type="string", example="Task description"),
     *             @OA\Property(property="status", type="string", enum={"pending","in_progress","completed"}),
     *             @OA\Property(property="priority", type="string", enum={"low","medium","high"}),
     *             @OA\Property(property="due_date", type="string", format="date", nullable=true)
     *         )
     *     ),
     *     @OA\Response(response=201, description="Task created", @OA\JsonContent(ref="#/components/schemas/TaskResponse")),
     *     @OA\Response(response=422, description="Validation error")
     * )
     */
    public function store(StoreTaskRequest $request): JsonResponse
    {
        $task = Task::create($request->validated());
        Log::info("Task created: id={$task->id} title={$task->title}");

        return response()->json(['status' => 'success', 'data' => $task], 201);
    }

    /**
     * Update Task
     * 
     * @OA\Put(
     *     path="/api/tasks/{id}",
     *     summary="Update a task",
     *     description="Update an existing task",
     *     tags={"Tasks"},
     *     @OA\Parameter(name="id", in="path", required=true, description="Task ID", @OA\Schema(type="integer")),
     *     @OA\RequestBody(
     *         required=true,
     *         @OA\JsonContent(
     *             @OA\Property(property="title", type="string", example="Updated Title"),
     *             @OA\Property(property="description", type="string"),
     *             @OA\Property(property="status", type="string", enum={"pending","in_progress","completed"}),
     *             @OA\Property(property="priority", type="string", enum={"low","medium","high"}),
     *             @OA\Property(property="due_date", type="string", format="date", nullable=true)
     *         )
     *     ),
     *     @OA\Response(response=200, description="Success", @OA\JsonContent(ref="#/components/schemas/TaskResponse")),
     *     @OA\Response(response=404, description="Task not found")
     * )
     */
    public function update(UpdateTaskRequest $request, Task $task): JsonResponse
    {
        $task->update($request->validated());
        Log::info("Task updated: id={$task->id}");

        return response()->json(['status' => 'success', 'data' => $task->fresh()]);
    }

    /**
     * Delete Task
     * 
     * @OA\Delete(
     *     path="/api/tasks/{id}",
     *     summary="Delete a task",
     *     description="Delete a task by ID",
     *     tags={"Tasks"},
     *     @OA\Parameter(name="id", in="path", required=true, description="Task ID", @OA\Schema(type="integer")),
     *     @OA\Response(response=200, description="Success", @OA\JsonContent(
     *         @OA\Property(property="status", type="string"),
     *         @OA\Property(property="message", type="string")
     *     )),
     *     @OA\Response(response=404, description="Task not found")
     * )
     */
    public function destroy(Task $task): JsonResponse
    {
        $id = $task->id;
        $task->delete();
        Log::info("Task deleted: id={$id}");

        return response()->json(['status' => 'success', 'message' => 'Task deleted'], 200);
    }

    /**
     * Mark Task Complete
     * 
     * @OA\Post(
     *     path="/api/tasks/{id}/complete",
     *     summary="Mark task as complete",
     *     description="Mark a task as completed",
     *     tags={"Tasks"},
     *     @OA\Parameter(name="id", in="path", required=true, description="Task ID", @OA\Schema(type="integer")),
     *     @OA\Response(response=200, description="Success", @OA\JsonContent(ref="#/components/schemas/TaskResponse")),
     *     @OA\Response(response=404, description="Task not found"),
     *     @OA\Response(response=409, description="Task already completed")
     * )
     */
    public function complete(Task $task): JsonResponse
    {
        if ($task->status === Task::STATUS_COMPLETED) {
            return response()->json(['status' => 'error', 'message' => 'Task is already completed'], 409);
        }

        $task->markAsCompleted();
        Log::info("Task marked completed: id={$task->id}");

        return response()->json(['status' => 'success', 'data' => $task->fresh()]);
    }
}