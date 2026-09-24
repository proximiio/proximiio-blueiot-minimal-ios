#!/usr/bin/env node
/**
 * Starts and controls LiveView journey runs from a terminal, a script or a
 * phone shortcut. It calls `/v1/runs`, the API the LiveView journey card uses.
 *
 * The API requires a Proximi.io **user** token, sent as `Authorization: Bearer`.
 * It refuses an application token with HTTP 403. `login` exchanges a Proximi.io
 * email and password for a user token (`POST /core_auth/login` on the Proximi.io
 * API) and writes it to a file with mode 0600. The other commands read the token
 * from `LIVEVIEW_TOKEN` or `--token-file`. The script never prints the token,
 * including with `--dry-run`.
 *
 * Usage (Node 22 or later; no dependencies):
 *   node scripts/journey-run.mjs login --token-file <path>
 *   node scripts/journey-run.mjs list [--place <place id>]
 *   node scripts/journey-run.mjs start <journey_id> [--relay <name>] [--walker N]
 *                                      [--ground-floor N] [--speed X] [--rate HZ]
 *                                      [--loop] [--preview]
 *   node scripts/journey-run.mjs status
 *   node scripts/journey-run.mjs pause|resume|stop <run_id>
 *
 * Options for every command:
 *   --token-file <path>   the token file; `login` writes it, the others read it
 *   --url <url>           the LiveView API; overrides LIVEVIEW_URL
 *   --dry-run             print the request with credentials redacted, send nothing
 *   --json                print the API response as JSON
 *
 * The LiveView API defaults to https://live.proximi.fi. `login` and `list` call
 * the Proximi.io API, `PROXIMIIO_API_URL`, default https://api.proximi.fi.
 * `list` does not go through LiveView because LiveView's proxy accepts only a
 * browser session cookie.
 *
 * `--ground-floor` is the floor number the receiving app uses for the ground
 * floor. Default 1: a BlueIoT LocalSense engine numbers the ground floor 1, and
 * the iOS BlueIoT apps set `BLUEIOT_GROUND_FLOOR_NO = 1`. Set it to the app's
 * value.
 *
 * `--walker N` selects which of the organisation's wristbands on the relay the
 * run plays as, 1..N. The server leases the wristband ids and lists them in
 * `/v1/config`; `start` and `status` print the walker and its tag id. Without
 * `--walker`, the server picks the lowest walker the organisation is not
 * already playing on that relay.
 *
 * `start` without `--preview` injects positions into a shared sandbox relay.
 * Every app that follows the walker's tag id on that relay receives them.
 */

import { readFileSync, openSync, fchmodSync, writeSync, closeSync } from 'node:fs'
import { createInterface } from 'node:readline'
import { Writable } from 'node:stream'

const USAGE = `usage:
  journey-run.mjs login --token-file <path>
  journey-run.mjs list [--place <place id>]
  journey-run.mjs start <journey_id> [--relay <name>] [--walker N] [--ground-floor N] [--speed X] [--rate HZ] [--loop] [--preview]
  journey-run.mjs status
  journey-run.mjs pause|resume|stop <run_id>
common: [--token-file <path>] [--url <liveview url>] [--dry-run] [--json]
env:    LIVEVIEW_URL (default https://live.proximi.fi), LIVEVIEW_TOKEN,
        PROXIMIIO_API_URL (login and list, default https://api.proximi.fi)`

const DEFAULT_LIVEVIEW_URL = 'https://live.proximi.fi'
const DEFAULT_PROXIMIIO_API_URL = 'https://api.proximi.fi'

const BOOLEAN_FLAGS = new Set(['loop', 'preview', 'dry-run', 'json', 'help'])

function parse(argv) {
  const positional = []
  const options = new Map()
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '-h') {
      options.set('help', true)
      continue
    }
    if (!arg.startsWith('--')) {
      positional.push(arg)
      continue
    }
    const [name, inline] = arg.slice(2).split(/=(.*)/s, 2)
    if (BOOLEAN_FLAGS.has(name)) {
      options.set(name, true)
      continue
    }
    const value = inline ?? argv[++i]
    if (value === undefined) fail(`--${name} needs a value`)
    options.set(name, value)
  }
  return { positional, options }
}

function fail(message, code = 2) {
  console.error(`journey-run: ${message}`)
  process.exit(code)
}

function number(options, name, { integer = false } = {}) {
  if (!options.has(name)) return undefined
  const value = Number(options.get(name))
  if (!Number.isFinite(value) || (integer && !Number.isInteger(value))) {
    fail(`--${name} must be ${integer ? 'a whole number' : 'a number'}`)
  }
  return value
}

function readToken(options) {
  let token
  if (options.has('token-file')) {
    try {
      token = readFileSync(options.get('token-file'), 'utf8')
    } catch (error) {
      fail(`cannot read --token-file: ${error.code ?? error.message}`)
    }
  } else {
    token = process.env.LIVEVIEW_TOKEN
  }
  token = (token ?? '').trim()
  if (!token) fail('no token: run `login --token-file <path>`, or set LIVEVIEW_TOKEN')
  if (/\s/.test(token)) fail('the token file must hold the token alone, on one line')
  return token
}

/** Refuses any base URL that is not https, except plain http to localhost. */
function checkedBase(raw, what) {
  let url
  try {
    url = new URL(raw)
  } catch {
    fail(`${what} is not a URL`)
  }
  const local = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && local)) {
    fail(`${what} must be https (plain http only for localhost), got ${url.protocol}//${url.host}`)
  }
  return url.origin
}

async function call(base, token, method, path, body, options) {
  const headers = { authorization: `Bearer ${token}`, accept: 'application/json' }
  if (body !== undefined) headers['content-type'] = 'application/json'

  if (options.get('dry-run')) {
    console.log(`${method} ${base}${path}`)
    console.log('authorization: Bearer <redacted>')
    if (body !== undefined) console.log(JSON.stringify(body, null, 2))
    process.exit(0)
  }

  let response
  try {
    response = await fetch(`${base}${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    })
  } catch (error) {
    fail(`${method} ${path}: ${error.cause?.code ?? error.message}`, 1)
  }
  const text = await response.text()
  let data = null
  try {
    data = text ? JSON.parse(text) : null
  } catch {
    data = null
  }
  if (!response.ok) {
    // LiveView API errors are `{ error: "…" }` and contain no credential.
    const reason = data?.error ?? data?.message ?? response.statusText
    const hint =
      response.status === 401
        ? ' (token unknown or revoked; run `login` again)'
        : response.status === 403 && /application token/.test(String(reason))
          ? ' (use a user token from `login`, not the app\'s application token)'
          : ''
    fail(`${method} ${path}: ${response.status} ${reason}${hint}`, 1)
  }
  return { data, response }
}

/**
 * Reads the email and the password from the terminal. The password is not
 * echoed. Without a terminal, reads two lines from standard input: the email,
 * then the password. Prompts go to standard error.
 */
async function promptCredentials() {
  let muted = false
  const output = new Writable({
    write(chunk, _encoding, callback) {
      if (!muted) process.stderr.write(chunk)
      callback()
    },
  })
  const terminal = Boolean(process.stdin.isTTY)
  const rl = createInterface({ input: process.stdin, output, terminal })
  rl.on('SIGINT', () => {
    process.stderr.write('\n')
    process.exit(130)
  })
  const lines = rl[Symbol.asyncIterator]()
  const next = async () => {
    const { value, done } = await lines.next()
    return done ? undefined : value
  }

  // A terminal echoes the email and its newline; piped input echoes nothing.
  const newline = () => process.stderr.write('\n')
  process.stderr.write('Proximi.io email: ')
  const email = (await next())?.trim()
  if (!terminal) newline()
  process.stderr.write('Password: ')
  muted = true
  const password = await next()
  muted = false
  newline()
  rl.close()

  if (!email) fail('no email given')
  if (!password) fail('no password given')
  return { email, password }
}

/**
 * Writes the token to `path` with mode 0600, replacing the file's contents.
 * The mode is set before the token is written, so an existing file with wider
 * permissions never holds the token readable by others.
 */
function writeTokenFile(path, token) {
  let fd
  try {
    fd = openSync(path, 'w', 0o600)
    fchmodSync(fd, 0o600)
    writeSync(fd, `${token}\n`)
  } catch (error) {
    fail(`cannot write --token-file: ${error.code ?? error.message}`, 1)
  } finally {
    if (fd !== undefined) closeSync(fd)
  }
}

async function login(options) {
  if (!options.has('token-file')) fail('login needs --token-file <path>: the file the token is written to')
  const path = options.get('token-file')
  const base = checkedBase(process.env.PROXIMIIO_API_URL ?? DEFAULT_PROXIMIIO_API_URL, 'PROXIMIIO_API_URL')
  const { email, password } = await promptCredentials()

  if (options.get('dry-run')) {
    console.log(`POST ${base}/core_auth/login`)
    console.log(JSON.stringify({ email, password: '<redacted>' }, null, 2))
    console.log(`would write the token to ${path} (mode 0600)`)
    process.exit(0)
  }

  let response
  try {
    response = await fetch(`${base}/core_auth/login`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify({ email, password }),
    })
  } catch (error) {
    fail(`POST /core_auth/login: ${error.cause?.code ?? error.message}`, 1)
  }
  const text = await response.text()
  if (!response.ok) {
    // The response body is not printed: it may repeat the email.
    const hint = response.status === 401 || response.status === 403 ? ' (email or password refused)' : ''
    fail(`POST /core_auth/login: ${response.status} ${response.statusText}${hint}`, 1)
  }
  let data = null
  try {
    data = JSON.parse(text)
  } catch {
    fail('POST /core_auth/login: the response is not JSON', 1)
  }
  // `token` is the user token. `application.token` in the same response is the
  // organisation's application token, which the LiveView API refuses.
  const token = data?.token
  if (typeof token !== 'string' || !token || /\s/.test(token)) {
    fail('POST /core_auth/login: the response carries no user token', 1)
  }
  writeTokenFile(path, token)
  const organisation = data?.organization?.name ?? data?.organization?.id ?? 'unknown organisation'
  console.log(`logged in as ${data?.user?.email ?? email} (${organisation}); token written to ${path}`)
}

function describeRun(run) {
  // The walker is the slot the run asked for; the tag id is the wristband id
  // the app is configured with.
  const where =
    run.sink === 'relay'
      ? `relay ${run.relay ?? '?'} walker ${run.walker ?? '?'} tag ${run.tag_id ?? '?'}`
      : 'preview'
  const bits = [
    run.id,
    run.state,
    `"${run.name ?? run.journey_id}"`,
    where,
    `ground_floor_no=${run.ground_floor_no}`,
    `speed=${run.speed}x`,
    `rate=${run.rate_hz}Hz`,
  ]
  if (run.loop ?? run.looping) bits.push('loop')
  if (run.error) bits.push(`error: ${run.error}`)
  return bits.join('  ')
}

async function main() {
  const major = Number(process.versions.node.split('.')[0])
  if (major < 22) fail(`Node 22 or later is required, this is ${process.version}`)
  const { positional, options } = parse(process.argv.slice(2))
  const [command, arg] = positional
  if (!command || options.get('help')) {
    console.log(USAGE)
    process.exit(command ? 0 : 2)
  }

  if (command === 'login') return login(options)

  const token = readToken(options)
  const json = options.get('json')

  if (command === 'list') {
    const base = checkedBase(process.env.PROXIMIIO_API_URL ?? DEFAULT_PROXIMIIO_API_URL, 'PROXIMIIO_API_URL')
    const query = new URLSearchParams({ from: '0', size: '100' })
    if (options.has('place')) query.set('place_id', options.get('place'))
    const { data, response } = await call(base, token, 'GET', `/v7/geo/journeys?${query}`, undefined, options)
    const journeys = Array.isArray(data) ? data : []
    if (json) return console.log(JSON.stringify(journeys, null, 2))
    if (journeys.length === 0) return console.log('no journeys in this organisation')
    for (const j of journeys) {
      console.log(`${j.id}  "${j.name ?? '(unnamed)'}"  ${j.waypoints?.length ?? 0} waypoints`)
    }
    const total = Number(response.headers.get('record-total'))
    if (Number.isFinite(total) && total > journeys.length) {
      console.log(`… ${total - journeys.length} more not shown`)
    }
    return
  }

  const base = checkedBase(
    options.get('url') ?? process.env.LIVEVIEW_URL ?? DEFAULT_LIVEVIEW_URL,
    'LIVEVIEW_URL',
  )

  switch (command) {
    case 'start': {
      if (!arg) fail('start needs a journey id (see `list`)')
      const preview = Boolean(options.get('preview'))
      const body = {
        journey_id: arg,
        sink: preview ? 'preview' : 'relay',
        // The receiving app's ground floor number. Default 1 (LocalSense).
        ground_floor_no: number(options, 'ground-floor', { integer: true }) ?? 1,
        loop: Boolean(options.get('loop')),
      }
      if (options.has('relay')) {
        if (preview) fail('--relay and --preview do not go together: a preview plays on the map only')
        body.relay = options.get('relay')
      }
      const walker = number(options, 'walker', { integer: true })
      if (walker !== undefined) {
        // A preview holds no wristband. The API would ignore the field, so the
        // combination is refused here.
        if (preview) fail('--walker and --preview do not go together: a preview holds no wristband')
        if (walker < 1) fail('--walker is a walker number, counting from 1')
        body.walker = walker
      }
      const speed = number(options, 'speed')
      if (speed !== undefined) body.speed = speed
      const rate = number(options, 'rate', { integer: true })
      if (rate !== undefined) body.rate_hz = rate
      const { data } = await call(base, token, 'POST', '/v1/runs', body, options)
      return console.log(json ? JSON.stringify(data, null, 2) : `started  ${describeRun(data)}`)
    }
    case 'status': {
      const { data } = await call(base, token, 'GET', '/v1/runs', undefined, options)
      const runs = data?.runs ?? []
      if (json) return console.log(JSON.stringify(runs, null, 2))
      if (runs.length === 0) return console.log('no runs')
      for (const run of runs) console.log(describeRun(run))
      return
    }
    case 'pause':
    case 'resume':
    case 'stop': {
      if (!arg) fail(`${command} needs a run id (see \`status\`)`)
      const path = `/v1/runs/${encodeURIComponent(arg)}/${command}`
      const { data } = await call(base, token, 'POST', path, {}, options)
      return console.log(json ? JSON.stringify(data, null, 2) : describeRun(data))
    }
    default:
      fail(`unknown command \`${command}\`\n${USAGE}`)
  }
}

main()
