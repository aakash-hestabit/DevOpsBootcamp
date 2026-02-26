'use strict';

const path = require('path');
const swaggerJsdoc = require('swagger-jsdoc');

const options = {
  definition: {
    openapi: '3.0.0',
    info: {
      title: 'Express PostgreSQL Users API',
      version: '1.0.0',
      description: 'REST API for user management built with Express.js and PostgreSQL',
      contact: { name: 'Aakash', email: 'aakash@hestabit.in' },
    },
    servers: [
      { url: 'http://localhost:3000', description: 'Development server' },
      { url: 'http://localhost:3000', description: 'Production server' }, //we can cahnge it to the production domain as per requirements 
    ],
    components: {
      schemas: {
        User: {
          type: 'object',
          properties: {
            id: { type: 'integer', example: 1 },
            username: { type: 'string', example: 'johndoe' },
            email: { type: 'string', format: 'email', example: 'john@example.com' },
            full_name: { type: 'string', example: 'John Doe' },
            created_at: { type: 'string', format: 'date-time' },
            updated_at: { type: 'string', format: 'date-time' },
          },
        },
        CreateUser: {
          type: 'object',
          required: ['username', 'email'],
          properties: {
            username: { type: 'string', minLength: 3, maxLength: 50, example: 'johndoe' },
            email: { type: 'string', format: 'email', example: 'john@example.com' },
            full_name: { type: 'string', maxLength: 100, example: 'John Doe' },
          },
        },
        UpdateUser: {
          type: 'object',
          properties: {
            username: { type: 'string', minLength: 3, maxLength: 50 },
            email: { type: 'string', format: 'email' },
            full_name: { type: 'string', maxLength: 100 },
          },
        },
        HealthResponse: {
          type: 'object',
          properties: {
            status: { type: 'string', example: 'healthy' },
            timestamp: { type: 'string', format: 'date-time' },
            uptime: { type: 'number', example: 3600 },
            database: {
              type: 'object',
              properties: {
                status: { type: 'string', example: 'connected' },
                pool: {
                  type: 'object',
                  properties: {
                    total: { type: 'integer' },
                    idle: { type: 'integer' },
                    active: { type: 'integer' },
                  },
                },
              },
            },
            environment: { type: 'string', example: 'production' },
            version: { type: 'string', example: '1.0.0' },
          },
        },
        Error: {
          type: 'object',
          properties: {
            status: { type: 'string', example: 'error' },
            message: { type: 'string' },
            errors: { type: 'array', items: { type: 'object' } },
          },
        },
      },
    },
    tags: [
      { name: 'Health', description: 'Service health and readiness' },
      { name: 'Users', description: 'User CRUD operations' },
    ],
  },
  apis: [path.join(__dirname, '../routes/*.js')],
};

const swaggerSpec = swaggerJsdoc(options);
module.exports = swaggerSpec;