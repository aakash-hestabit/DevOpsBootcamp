@extends('layouts.app')

@section('title', 'Tasks')

@section('content')
<div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
    <h2 style="font-size: 1.5rem; font-weight: 600;">Tasks</h2>
    <a href="{{ route('tasks.create') }}" class="btn btn-primary">New Task</a>
</div>

<div class="card">
    @if($tasks->count() > 0)
    <table>
        <thead>
            <tr>
                <th>Title</th>
                <th>Status</th>
                <th>Priority</th>
                <th>Due Date</th>
                <th>Created</th>
                <th>Actions</th>
            </tr>
        </thead>
        <tbody>
            @foreach($tasks as $task)
            <tr>
                <td>
                    <strong>{{ $task->title }}</strong>
                    @if($task->description)
                        <br><span style="color: #6b7280; font-size: 0.75rem;">{{ Str::limit($task->description, 60) }}</span>
                    @endif
                </td>
                <td><span class="badge badge-{{ $task->status }}">{{ str_replace('_', ' ', $task->status) }}</span></td>
                <td><span class="badge badge-{{ $task->priority }}">{{ $task->priority }}</span></td>
                <td>{{ $task->due_date ? $task->due_date->format('M d, Y') : '-' }}</td>
                <td>{{ $task->created_at->diffForHumans() }}</td>
                <td>
                    <div class="actions">
                        @if($task->status !== 'completed')
                        <form action="{{ route('tasks.complete', $task) }}" method="POST">
                            @csrf
                            <button type="submit" class="btn btn-success btn-sm" title="Mark completed">Done</button>
                        </form>
                        @endif

                        <a href="{{ route('tasks.edit', $task) }}" class="btn btn-secondary btn-sm">Edit</a>

                        <form action="{{ route('tasks.destroy', $task) }}" method="POST" onsubmit="return confirm('Delete this task?')">
                            @csrf
                            @method('DELETE')
                            <button type="submit" class="btn btn-danger btn-sm">Del</button>
                        </form>
                    </div>
                </td>
            </tr>
            @endforeach
        </tbody>
    </table>

    <div class="pagination">
        @if($tasks->previousPageUrl())
            <a href="{{ $tasks->previousPageUrl() }}">Previous</a>
        @endif

        @for($i = 1; $i <= $tasks->lastPage(); $i++)
            @if($i == $tasks->currentPage())
                <span class="current">{{ $i }}</span>
            @else
                <a href="{{ $tasks->url($i) }}">{{ $i }}</a>
            @endif
        @endfor

        @if($tasks->nextPageUrl())
            <a href="{{ $tasks->nextPageUrl() }}">Next</a>
        @endif
    </div>
    @else
    <p style="text-align: center; padding: 2rem; color: #6b7280;">
        No tasks yet. <a href="{{ route('tasks.create') }}" style="color: #2563eb;">Create your first task</a>.
    </p>
    @endif
</div>
@endsection
