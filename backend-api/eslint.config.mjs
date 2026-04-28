// ESLint flat config (ESLint 9). Conservative ruleset:
// - Structural rules as `error` (catch real bugs).
// - Opinionated rules as `warn` (don't break legacy code).
// - Formatting left out (no Prettier integration in this scope).
import tsParser from '@typescript-eslint/parser';
import tsPlugin from '@typescript-eslint/eslint-plugin';

export default [
  {
    ignores: ['dist/**', 'node_modules/**', 'coverage/**'],
  },
  {
    files: ['**/*.ts'],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        ecmaVersion: 2022,
        sourceType: 'module',
      },
    },
    plugins: {
      '@typescript-eslint': tsPlugin,
    },
    rules: {
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^_',
        },
      ],
      '@typescript-eslint/no-explicit-any': 'warn',
      'no-console': 'warn',
    },
  },
  // Override: seed scripts are CLI standalone (no Nest DI / Logger).
  {
    files: ['**/database/seeds/**/*.ts'],
    rules: {
      'no-console': 'off',
    },
  },
];
