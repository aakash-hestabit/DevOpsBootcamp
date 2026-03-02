<?php

use App\Models\Task;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

// Main task dashboard
Route::get('/', function () {
    $tasks = Task::orderBy('created_at', 'desc')->paginate(10);
    return view('tasks.index', compact('tasks'));
})->name('tasks.index');

// Create task form
Route::get('/tasks/create', function () {
    return view('tasks.create');
})->name('tasks.create');

// Store new task
Route::post('/tasks', function (Request $request) {
    $validated = $request->validate([
        'title'       => 'required|string|max:255',
        'description' => 'nullable|string',
        'status'      => 'required|in:pending,in_progress,completed',
        'priority'    => 'required|in:low,medium,high',
        'due_date'    => 'nullable|date',
    ]);

    Task::create($validated);
    return redirect()->route('tasks.index')->with('success', 'Task created.');
})->name('tasks.store');

// Edit task form
Route::get('/tasks/{task}/edit', function (Task $task) {
    return view('tasks.edit', compact('task'));
})->name('tasks.edit');

// Update task
Route::put('/tasks/{task}', function (Request $request, Task $task) {
    $validated = $request->validate([
        'title'       => 'required|string|max:255',
        'description' => 'nullable|string',
        'status'      => 'required|in:pending,in_progress,completed',
        'priority'    => 'required|in:low,medium,high',
        'due_date'    => 'nullable|date',
    ]);

    $task->update($validated);
    return redirect()->route('tasks.index')->with('success', 'Task updated.');
})->name('tasks.update');

// Delete task
Route::delete('/tasks/{task}', function (Task $task) {
    $task->delete();
    return redirect()->route('tasks.index')->with('success', 'Task deleted.');
})->name('tasks.destroy');

// Mark task as completed
Route::post('/tasks/{task}/complete', function (Task $task) {
    $task->markAsCompleted();
    return redirect()->route('tasks.index')->with('success', 'Task marked as completed.');
})->name('tasks.complete');
