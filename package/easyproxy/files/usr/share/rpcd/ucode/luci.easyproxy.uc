#!/usr/bin/env ucode
'use strict';

// EasyProxy rpcd bridge.
//
// The LuCI panel runs the CLI through this ubus object. It exists because
// `fs.exec()` needs ubus `file exec`, and rpcd-mod-file dropped that method
// (OpenWrt 24.10 and later export only read / write / list / lstat), so every
// button on the panel silently failed on a current firmware while the ACL was
// correct and the CLI itself worked.
//
// Constraints kept from the file-exec design:
//   * the only binary ever spawned is /usr/sbin/easyproxy;
//   * the first argument must be one of the known subcommands below;
//   * every argument is single-quoted before it reaches the shell, so a value
//     such as "; cat /etc/shadow" stays one literal argument.

import { popen } from 'fs';

const BIN = '/usr/sbin/easyproxy';

const SAFE = [
	'status', 'validate', 'engine', 'node', 'rule', 'config', 'ruleset',
	'doctor', 'diag', 'update', 'start', 'stop', 'restart', 'bypass',
	'transparent', 'log', 'traffic', 'subscribe', 'uninstall-clean', 'version'
];

function quote(s) {
	return "'" + replace('' + s, "'", "'\"'\"'") + "'";
}

function allowed(sub) {
	for (let s in SAFE)
		if (s == sub)
			return true;
	return false;
}

const methods = {
	run: {
		// rpcd only passes string arguments reliably on this stack, so argv
		// arrives as a JSON array serialised into one string.
		args: { payload: 'string' },
		call: function(req) {
			let raw = null;
			try { raw = req.args.payload; } catch (e) { raw = null; }

			let argv = null;
			if (raw != null) {
				try {
					let v = json(raw);
					if (type(v) == 'array')
						argv = v;
				} catch (e) {
					argv = null;
				}
			}
			if (!argv || length(argv) < 1)
				return { code: 2, stdout: '', stderr: 'missing args' };
			if (!allowed('' + argv[0]))
				return { code: 2, stdout: '', stderr: 'refused subcommand: ' + argv[0] };

			let cmd = BIN;
			for (let a in argv)
				cmd += ' ' + quote(a);
			cmd += ' 2>&1';

			let p = popen(cmd, 'r');
			if (!p)
				return { code: 127, stdout: '', stderr: 'spawn failed' };
			let out = p.read('all');
			let rc = p.close();
			return { code: (rc == null) ? 0 : rc, stdout: (out == null) ? '' : out, stderr: '' };
		}
	}
};

return { 'easyproxy': methods };
