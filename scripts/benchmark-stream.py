"""Measure first real streamed tokens using synthetic prompts; never print credentials."""
import argparse
import json
import time
import urllib.request
import uuid
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(r'C:\AI\yanai'))
    parser.add_argument('--url', default='http://127.0.0.1:8081/v1/chat/completions')
    parser.add_argument('--webui', action='store_true', help='Sign in using saved bootstrap credentials')
    parser.add_argument('--ui-context', action='store_true', help='Include WebUI session metadata to exercise its UI tool-injection path')
    parser.add_argument('--model')
    parser.add_argument('--prompt', default='What is 17 plus 25? Answer in one sentence.')
    parser.add_argument('--max-tokens', type=int, default=32)
    parser.add_argument('--repeat', type=int, default=1)
    parser.add_argument('--no-cache', action='store_true')
    args = parser.parse_args()
    config = json.loads((args.root / '.secrets' / 'webui.json').read_text(encoding='utf-8-sig'))
    model = args.model or config['DefaultModel']
    if args.webui:
        credentials = (args.root / '.secrets' / 'first-login.json').read_bytes()
        base = args.url.split('/api/', 1)[0]
        req = urllib.request.Request(base + '/api/v1/auths/signin', data=credentials,
                                     headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(req, timeout=30) as response:
            key = json.load(response)['token']
    else:
        key = (args.root / '.secrets' / 'llama-api-key.txt').read_text().strip()
    for i in range(args.repeat):
        body = {'model': model, 'stream': True, 'max_tokens': args.max_tokens,
                'messages': [{'role': 'user', 'content': args.prompt}],
                'stream_options': {'include_usage': True}}
        if args.no_cache:
            body['cache_prompt'] = False
        if args.ui_context:
            body['session_id'] = 'yanai-benchmark-' + uuid.uuid4().hex
            body['features'] = {}
        req = urllib.request.Request(args.url, data=json.dumps(body).encode(),
                                     headers={'Content-Type': 'application/json',
                                              'Authorization': 'Bearer ' + key})
        started = time.perf_counter()
        first_thinking = first_answer = first_event = None
        reasoning_chars = answer_chars = chunks = 0
        usage = timings = finish = None
        with urllib.request.urlopen(req, timeout=900) as response:
            headers_at = time.perf_counter() - started
            for line in response:
                if not line.startswith(b'data: '):
                    continue
                raw = line[6:].strip()
                if raw == b'[DONE]':
                    break
                event = json.loads(raw)
                if 'error' in event:
                    raise RuntimeError('Streaming request returned an error')
                now = time.perf_counter() - started
                first_event = now if first_event is None else first_event
                usage = event.get('usage') or usage
                timings = event.get('timings') or timings
                for choice in event.get('choices', []):
                    delta = choice.get('delta', {})
                    reasoning = delta.get('reasoning_content') or delta.get('reasoning') or ''
                    answer = delta.get('content') or ''
                    if reasoning.strip() and first_thinking is None:
                        first_thinking = now
                    if answer.strip() and first_answer is None:
                        first_answer = now
                    reasoning_chars += len(reasoning)
                    answer_chars += len(answer)
                    chunks += bool(reasoning or answer)
                    finish = choice.get('finish_reason') or finish
        result = {'run': i + 1, 'model': model, 'url': args.url,
                  'headers_s': headers_at, 'first_event_s': first_event,
                  'first_thinking_s': first_thinking, 'first_answer_s': first_answer,
                  'elapsed_s': time.perf_counter() - started, 'content_chunks': chunks,
                  'reasoning_chars': reasoning_chars, 'answer_chars': answer_chars,
                  'finish_reason': finish, 'usage': usage, 'timings': timings}
        result = {k: round(v, 3) if isinstance(v, float) else v for k, v in result.items()}
        print(json.dumps(result), flush=True)


if __name__ == '__main__':
    main()
