@extends('layouts.app')

@section('title', 'Create Task')

@section('content')
<div style="margin-bottom: 1rem;">
    <a href="{{ route('tasks.index') }}" style="color: #2563eb; text-decoration: none; font-size: 0.875rem;">Back to Tasks</a>
</div>

<h2 style="font-size: 1.5rem; font-weight: 600; margin-bottom: 1rem;">Create Task</h2>

<div class="card">
    <form action="{{ route('tasks.store') }}" method="POST">
        @csrf

        <div class="form-group">
            <label for="title">Title</label>
            <input type="text" name="title" id="title" value="{{ old('title') }}" required placeholder="Task title">
            @error('title') <div class="form-error">{{ $message }}</div> @enderror
        </div>

        <div class="form-group">
            <label for="description">Description</label>
            <textarea name="description" id="description" placeholder="Optional description">{{ old('description') }}</textarea>
            @error('description') <div class="form-error">{{ $message }}</div> @enderror
        </div>

        <div style="display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 1rem;">
            <div class="form-group">
                <label for="status">Status</label>
                <select name="status" id="status">
                    <option value="pending" {{ old('status') == 'pending' ? 'selected' : '' }}>Pending</option>
                    <option value="in_progress" {{ old('status') == 'in_progress' ? 'selected' : '' }}>In Progress</option>
                    <option value="completed" {{ old('status') == 'completed' ? 'selected' : '' }}>Completed</option>
                </select>
                @error('status') <div class="form-error">{{ $message }}</div> @enderror
            </div>

            <div class="form-group">
                <label for="priority">Priority</label>
                <select name="priority" id="priority">
                    <option value="low" {{ old('priority') == 'low' ? 'selected' : '' }}>Low</option>
                    <option value="medium" {{ old('priority', 'medium') == 'medium' ? 'selected' : '' }}>Medium</option>
                    <option value="high" {{ old('priority') == 'high' ? 'selected' : '' }}>High</option>
                </select>
                @error('priority') <div class="form-error">{{ $message }}</div> @enderror
            </div>

            <div class="form-group">
                <label for="due_date">Due Date</label>
                <input type="date" name="due_date" id="due_date" value="{{ old('due_date') }}">
                @error('due_date') <div class="form-error">{{ $message }}</div> @enderror
            </div>
        </div>

        <div style="display: flex; gap: 0.5rem; margin-top: 0.5rem;">
            <button type="submit" class="btn btn-primary">Create Task</button>
            <a href="{{ route('tasks.index') }}" class="btn btn-secondary">Cancel</a>
        </div>
    </form>
</div>
@endsection
