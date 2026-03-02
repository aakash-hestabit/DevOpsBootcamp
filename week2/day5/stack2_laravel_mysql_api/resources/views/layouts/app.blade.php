<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>@yield('title', 'Task Manager') - Stack 2</title>
    <style>
        /* Minimal CSS -- no external dependencies required */
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #f3f4f6; color: #1f2937; line-height: 1.6;
        }
        .container { max-width: 960px; margin: 0 auto; padding: 0 1rem; }

        /* Header */
        header { background: #1e293b; color: #fff; padding: 1rem 0; }
        header .container { display: flex; justify-content: space-between; align-items: center; }
        header h1 { font-size: 1.25rem; font-weight: 600; }
        header nav a {
            color: #94a3b8; text-decoration: none; margin-left: 1.5rem;
            font-size: 0.875rem; transition: color .15s;
        }
        header nav a:hover { color: #fff; }

        /* Flash messages */
        .alert {
            padding: 0.75rem 1rem; border-radius: 6px; margin-bottom: 1rem;
            font-size: 0.875rem;
        }
        .alert-success { background: #dcfce7; color: #166534; border: 1px solid #bbf7d0; }
        .alert-error   { background: #fef2f2; color: #991b1b; border: 1px solid #fecaca; }

        /* Cards */
        .card {
            background: #fff; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,.1);
            padding: 1.5rem; margin-bottom: 1rem;
        }

        /* Table */
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 0.75rem; text-align: left; border-bottom: 1px solid #e5e7eb; font-size: 0.875rem; }
        th { font-weight: 600; color: #6b7280; text-transform: uppercase; font-size: 0.75rem; letter-spacing: 0.05em; }
        tr:hover { background: #f9fafb; }

        /* Badges */
        .badge {
            display: inline-block; padding: 0.15rem 0.5rem; border-radius: 9999px;
            font-size: 0.75rem; font-weight: 600; text-transform: capitalize;
        }
        .badge-pending     { background: #fef3c7; color: #92400e; }
        .badge-in_progress { background: #dbeafe; color: #1e40af; }
        .badge-completed   { background: #dcfce7; color: #166534; }
        .badge-low    { background: #f3f4f6; color: #6b7280; }
        .badge-medium { background: #fef3c7; color: #92400e; }
        .badge-high   { background: #fef2f2; color: #991b1b; }

        /* Buttons */
        .btn {
            display: inline-block; padding: 0.5rem 1rem; border-radius: 6px;
            font-size: 0.875rem; font-weight: 500; text-decoration: none;
            border: 1px solid transparent; cursor: pointer; transition: background .15s;
        }
        .btn-primary   { background: #2563eb; color: #fff; }
        .btn-primary:hover { background: #1d4ed8; }
        .btn-secondary { background: #e5e7eb; color: #374151; }
        .btn-secondary:hover { background: #d1d5db; }
        .btn-success   { background: #16a34a; color: #fff; }
        .btn-success:hover { background: #15803d; }
        .btn-danger    { background: #dc2626; color: #fff; }
        .btn-danger:hover { background: #b91c1c; }
        .btn-sm { padding: 0.25rem 0.5rem; font-size: 0.75rem; }

        /* Forms */
        .form-group { margin-bottom: 1rem; }
        .form-group label {
            display: block; font-size: 0.875rem; font-weight: 500;
            color: #374151; margin-bottom: 0.25rem;
        }
        .form-group input, .form-group select, .form-group textarea {
            width: 100%; padding: 0.5rem 0.75rem; border: 1px solid #d1d5db;
            border-radius: 6px; font-size: 0.875rem; background: #fff;
            transition: border-color .15s;
        }
        .form-group input:focus, .form-group select:focus, .form-group textarea:focus {
            outline: none; border-color: #2563eb; box-shadow: 0 0 0 3px rgba(37,99,235,.1);
        }
        .form-group textarea { resize: vertical; min-height: 80px; }
        .form-error { color: #dc2626; font-size: 0.75rem; margin-top: 0.25rem; }

        /* Action buttons inline */
        .actions { display: flex; gap: 0.5rem; align-items: center; }
        .actions form { display: inline; }

        /* Pagination */
        .pagination { display: flex; gap: 0.25rem; justify-content: center; padding: 1rem 0; }
        .pagination a, .pagination span {
            padding: 0.5rem 0.75rem; border-radius: 6px; font-size: 0.875rem;
            text-decoration: none; border: 1px solid #d1d5db; color: #374151;
        }
        .pagination span.current { background: #2563eb; color: #fff; border-color: #2563eb; }
        .pagination a:hover { background: #f3f4f6; }

        /* Footer */
        footer { text-align: center; padding: 2rem 0; color: #9ca3af; font-size: 0.75rem; }

        main { padding: 1.5rem 0; }
    </style>
</head>
<body>
    <header>
        <div class="container">
            <h1>Stack 2 - Task Manager</h1>
            <nav>
                <a href="{{ route('tasks.index') }}">Tasks</a>
                <a href="{{ route('tasks.create') }}">New Task</a>
                <a href="/api/health" target="_blank">Health</a>
            </nav>
        </div>
    </header>

    <main>
        <div class="container">
            @if(session('success'))
                <div class="alert alert-success">{{ session('success') }}</div>
            @endif

            @if($errors->any())
                <div class="alert alert-error">
                    <ul style="list-style: disc; padding-left: 1rem;">
                        @foreach($errors->all() as $error)
                            <li>{{ $error }}</li>
                        @endforeach
                    </ul>
                </div>
            @endif

            @yield('content')
        </div>
    </main>

    <footer>
        <div class="container">
            Stack 2: Laravel + MySQL | {{ config('app.env') }} | PHP {{ PHP_VERSION }}
        </div>
    </footer>
</body>
</html>
