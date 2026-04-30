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
  // ---------------------------------------------------
  // Override: test files
  //
  // Mocks parciais com `: any` são padrão idiomático no
  // ecossistema Jest + NestJS. Tipar mocks com
  // Partial<Repository<X>>, jest.Mocked<X>, ou helpers
  // custom adiciona ~300 linhas de boilerplate sem ganho
  // de type safety real (testes validam comportamento de
  // CHAMADA, não tipagem de retorno).
  //
  // Investigação documentada: Partial<Repository<X>>
  // quebra em overloads de save/create e em
  // .mockResolvedValue() (não existe na assinatura
  // tipada do Repository real). Override é a decisão
  // tecnicamente correta para esse contexto.
  //
  // Outras regras (no-unused-vars, no-console) seguem
  // ativas em test/.
  // ---------------------------------------------------
  {
    files: ['test/**/*.ts'],
    rules: {
      '@typescript-eslint/no-explicit-any': 'off',
    },
  },
];
