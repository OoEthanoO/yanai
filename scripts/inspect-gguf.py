"""Inspect GGUF metadata and tensor types without loading model weights into RAM."""
import argparse
import collections
import json
import struct


def inspect(path):
    with open(path, 'rb') as file:
        def read(fmt):
            return struct.unpack('<' + fmt, file.read(struct.calcsize('<' + fmt)))[0]

        def string():
            return file.read(read('Q')).decode('utf-8')

        formats = {0: 'B', 1: 'b', 2: 'H', 3: 'h', 4: 'I', 5: 'i',
                   6: 'f', 7: '?', 10: 'Q', 11: 'q', 12: 'd'}

        def value(kind, keep=True):
            if kind == 8:
                length = read('Q')
                if keep:
                    return file.read(length).decode('utf-8')
                file.seek(length, 1)
            elif kind == 9:
                subtype, count = read('I'), read('Q')
                if subtype in formats:
                    file.seek(count * struct.calcsize('<' + formats[subtype]), 1)
                else:
                    for _ in range(count):
                        value(subtype, keep=False)
            else:
                return read(formats[kind])

        if file.read(4) != b'GGUF':
            raise ValueError('Not a GGUF file')
        version, tensor_count, metadata_count = read('I'), read('Q'), read('Q')
        if version != 3:
            raise ValueError(f'Unsupported GGUF version: {version}')
        metadata = {}
        for _ in range(metadata_count):
            key, kind = string(), read('I')
            keep = key.startswith('general.') or key.endswith('.context_length')
            result = value(kind, keep)
            if keep:
                metadata[key] = result
        types = collections.Counter()
        for _ in range(tensor_count):
            string()
            dimensions = read('I')
            file.seek(dimensions * 8, 1)
            types[read('I')] += 1
            read('Q')
        names = {0: 'F32', 1: 'F16', 30: 'BF16'}
        return {'path': str(path), 'metadata': metadata, 'tensor_count': tensor_count,
                'tensor_types': {names.get(k, f'type_{k}'): v for k, v in types.items()},
                'unquantized': set(types).issubset(names)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('files', nargs='+')
    parser.add_argument('--require-unquantized', action='store_true')
    args = parser.parse_args()
    for path in args.files:
        result = inspect(path)
        print(json.dumps(result))
        if args.require_unquantized and not result['unquantized']:
            raise SystemExit('Quantized tensors found')
