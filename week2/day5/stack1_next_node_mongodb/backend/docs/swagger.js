'use strict';

const path = require('path');
const swaggerJsdoc = require('swagger-jsdoc');

const options = {
  definition: {
    openapi: '3.0.0',
    info: {
      title: 'Express MongoDB Users API',
      version: '1.0.0',
      description: 'REST API for user management built with Express.js and MongoDB',
    },
    servers: [
      { url: 'http://localhost:3000', description: 'Instance 1 (dev)' },
      { url: 'http://localhost:3003', description: 'Instance 2' },
      { url: 'http://localhost:3004', description: 'Instance 3' },
    ],
    components: {
      schemas: {
        User: {
          type: 'object',
          properties: {
            id: { type: 'string', example: '65c1234abcd5678ef90abcde' },
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
      },
    },
    tags: [
      { name: 'Health', description: 'Service health and readiness' },
      { name: 'Users', description: 'User CRUD operations' },
    ],
  },
  apis: [path.join(__dirname, '../routes/*.js')],
};

module.exports = swaggerJsdoc(options);