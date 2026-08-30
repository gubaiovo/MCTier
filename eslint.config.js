import js from '@eslint/js';
import globals from 'globals';
import reactHooks from 'eslint-plugin-react-hooks';
import reactRefresh from 'eslint-plugin-react-refresh';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  { ignores: ['dist', 'node_modules', 'build', '*.config.js', '*.config.ts'] },
  {
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
    files: ['**/*.{ts,tsx}'],
    languageOptions: {
      ecmaVersion: 2021,
      globals: globals.browser,
    },
    plugins: {
      'react-hooks': reactHooks,
      'react-refresh': reactRefresh,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      'react-refresh/only-export-components': [
        'warn',
        { allowConstantExport: true },
      ],
      // TypeScript 规则
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/explicit-function-return-type': 'off',
      '@typescript-eslint/explicit-module-boundary-types': 'off',
      '@typescript-eslint/no-unused-vars': [
        'warn',
        {
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
        },
      ],
      '@typescript-eslint/no-non-null-assertion': 'warn',
      // 通用规则
      'no-console': ['warn', { allow: ['warn', 'error'] }],
      'no-debugger': 'warn',
      'prefer-const': 'warn',
      'no-var': 'error',
      // `value == null` is intentionally used when both null and undefined
      // mean "not supplied". Keep strict equality everywhere else.
      eqeqeq: ['error', 'always', { null: 'ignore' }],
      // These expressions deliberately reject control characters at trust
      // boundaries; replacing them with less readable loops would weaken the
      // auditability of the validation code.
      'no-control-regex': 'off',
      // Signaling dispatch cases always terminate locally. TypeScript already
      // rejects colliding declarations, so extra braces add no safety here.
      'no-case-declarations': 'off',
      // Several controlled inputs synchronize modal-local draft state when a
      // modal opens. This is an intentional external-prop synchronization.
      'react-hooks/set-state-in-effect': 'off',
    },
  }
);
