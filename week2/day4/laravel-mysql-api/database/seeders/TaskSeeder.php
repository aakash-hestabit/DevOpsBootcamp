<?php

namespace Database\Seeders;

use App\Models\Task;
use Illuminate\Database\Seeder;

class TaskSeeder extends Seeder
{
    public function run(): void
    {
        $tasks = [
            ['title' => 'Set up CI/CD pipeline',       'status' => 'in_progress', 'priority' => 'high',   'description' => 'Configure GitHub Actions for automated deployment'],
            ['title' => 'Write API documentation',      'status' => 'pending',     'priority' => 'medium', 'description' => 'Document all REST endpoints with request/response examples'],
            ['title' => 'Configure monitoring alerts',   'status' => 'pending',     'priority' => 'high',   'description' => 'Set up PagerDuty alerts for downtime events'],
            ['title' => 'Database backup automation',   'status' => 'completed',   'priority' => 'high',   'description' => 'Cron job for nightly MySQL dumps to S3'],
            ['title' => 'Code review process',          'status' => 'pending',     'priority' => 'low',    'description' => 'Define pull request review guidelines for the team'],
        ];

        foreach ($tasks as $task) {
            Task::create($task);
        }

        $this->command->info('Seeded ' . count($tasks) . ' tasks');
    }
}