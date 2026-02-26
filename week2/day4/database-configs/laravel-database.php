<?php
/**
 * Laravel MySQL connection pool configuration reference.
 * Actual config is in laravel-mysql-api/config/database.php
 */

return [
    'default' => env('DB_CONNECTION', 'mysql'),

    'connections' => [
        'mysql' => [
            'driver'    => 'mysql',
            'host'      => env('DB_HOST', '127.0.0.1'),
            'port'      => env('DB_PORT', '3306'),
            'database'  => env('DB_DATABASE', 'laraveldb'),
            'username'  => env('DB_USERNAME', 'laraveluser'),
            'password'  => env('DB_PASSWORD', ''),
            'charset'   => 'utf8mb4',
            'collation' => 'utf8mb4_unicode_ci',
            'prefix'    => '',
            'strict'    => true,
            'engine'    => 'InnoDB',
            'options'   => extension_loaded('pdo_mysql') ? array_filter([
                // PDO persistent connections - reuse OS-level TCP connections
                PDO::ATTR_PERSISTENT       => true,
                // Disable emulated prepares - uses real server-side prepared statements
                PDO::ATTR_EMULATE_PREPARES => false,
            ]) : [],
        ],
    ],
];