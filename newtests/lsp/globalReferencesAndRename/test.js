/**
 * @flow
 * @format
 */

import type {Suite} from 'flow-dev-tools/src/test/Suite';
const {readFileSync, readdirSync} = require('fs');
const {join} = require('path');
const {suite, test} = require('flow-dev-tools/src/test/Tester');

/**
 * The code in findReferences shares the same logic as documentHighlight. That test suite is
 * much more comprehensive and covers the more complex behaviors of findReferences. Rather than
 * duplicate the test suites, this test just sanity checks that findReferences is working end-to-end
 */
module.exports = (suite(
  ({
    lspNotification,
    lspStartAndConnect,
    lspRequestAndWaitUntilResponse,
    addFiles,
  }) => {
    function findAllRefsSnapshot(
      fixture: string,
      line: number,
      col: number,
      expectedFile: string,
    ) {
      return lspRequestAndWaitUntilResponse('textDocument/references', {
        textDocument: {
          uri: `<PLACEHOLDER_PROJECT_URL>/__fixtures__/${fixture}`,
        },
        position: {line: line, character: col},
      }).verifyLSPMessageSnapshot(
        join(__dirname, '__snapshots__', 'references', expectedFile),
        [
          'textDocument/publishDiagnostics',
          'window/showStatus',
          '$/cancelRequest',
        ],
      );
    }
    function globalRenameSnapshot(
      fixture: string,
      line: number,
      col: number,
      expectedFile: string,
    ) {
      return lspRequestAndWaitUntilResponse('textDocument/rename', {
        textDocument: {
          uri: `<PLACEHOLDER_PROJECT_URL>/__fixtures__/${fixture}`,
        },
        position: {line: line, character: col},
        newName: 'NEW_NAME',
      }).verifyLSPMessageSnapshot(
        join(__dirname, '__snapshots__', 'rename', expectedFile),
        [
          'textDocument/publishDiagnostics',
          'window/showStatus',
          '$/cancelRequest',
        ],
      );
    }
    const fixtures = readdirSync(join(__dirname, '__fixtures__')).map(file =>
      join('__fixtures__', file),
    );
    return [
      test('Find all refs from properties', [
        addFiles(...fixtures),
        lspStartAndConnect(),
        findAllRefsSnapshot('use-prop-site-a.js', 5, 6, 'prop_defs_1.json'),
        findAllRefsSnapshot('use-prop-site-b.js', 5, 6, 'prop_defs_2.json'),
      ]),
      test('Find all refs from identifiers', [
        addFiles(...fixtures),
        lspStartAndConnect(),
        findAllRefsSnapshot(
          'identifiers-def.js',
          2,
          14,
          'identifiers-def-1.json',
        ),
        findAllRefsSnapshot(
          'identifiers-def.js',
          3,
          17,
          'identifiers-def-2.json',
        ),
        findAllRefsSnapshot(
          'use-exported-identifiers-site-b.js',
          8,
          12,
          'identifiers-def-3.json',
        ),
      ]),
      test('Global rename property 1', [
        addFiles(...fixtures),
        lspStartAndConnect(),
        globalRenameSnapshot('use-prop-site-a.js', 5, 6, 'prop_defs_1.json'),
      ]),
      test('Global rename property 2', [
        addFiles(...fixtures),
        lspStartAndConnect(),
        globalRenameSnapshot('use-prop-site-b.js', 5, 6, 'prop_defs_2.json'),
      ]),
      test('Global rename identifier 1', [
        addFiles(...fixtures),
        lspStartAndConnect(),
        globalRenameSnapshot(
          'identifiers-def.js',
          2,
          14,
          'identifiers-def-1.json',
        ),
      ]),
      test('Global rename identifier 2', [
        addFiles(...fixtures),
        lspStartAndConnect(),
        globalRenameSnapshot(
          'identifiers-def.js',
          3,
          17,
          'identifiers-def-2.json',
        ),
      ]),
    ];
  },
): Suite);
