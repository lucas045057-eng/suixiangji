"""Bounded SSE framing and incremental top-level semantic object extraction."""
import codecs
import json

from .batch_llm import _invalid_constant, _unique_object


class StreamFailure(Exception):
    def __init__(self, code, retry_after_seconds=None):
        self.code = code
        self.retry_after_seconds = retry_after_seconds
        super().__init__(code)


def strict_json(text):
    return json.loads(text, object_pairs_hook=_unique_object, parse_constant=_invalid_constant)


class SSEDecoder:
    """SSE records, including CR/CRLF and multiline data, across UTF-8 chunks."""
    def __init__(self):
        self.decoder = codecs.getincrementaldecoder("utf-8")("strict")
        self.line = ""
        self.data = []
        self.size = 0
        self.after_cr = False

    def feed(self, chunk, final=False):
        try:
            text = self.decoder.decode(chunk, final=final)
        except UnicodeError:
            raise StreamFailure("stream_protocol_error") from None
        records = []
        for char in text:
            if self.after_cr and char == "\n":
                self.after_cr = False
                continue
            self.after_cr = char == "\r"
            if char in "\r\n":
                line, self.line = self.line, ""
                if not line:
                    if self.data:
                        records.append("\n".join(self.data))
                    self.data, self.size = [], 0
                elif line.startswith("data:"):
                    value = line[5:]
                    self.data.append(value[1:] if value.startswith(" ") else value)
                continue
            self.line += char
            self.size += 1
            if self.size > 262144:
                raise StreamFailure("stream_protocol_error")
        # A non-dispatched final record is deliberately not repaired at EOF.
        return records


class PlanScanner:
    """Lexical stack avoids matching 'items' inside strings or nested objects.

    Full grammar/duplicate-key validation is deferred to parse_plan. Only
    strictly parsed, individually validated closed objects may become previews.
    """
    def __init__(self):
        self.content = ""
        self.stack = []
        self.quoted = False
        self.escaped = False
        self.string_start = 0
        self.key = None
        self.expect_key = True
        self.ordinal = 0

    def feed(self, delta):
        start = len(self.content)
        self.content += delta
        if len(self.content) > 65536:
            raise StreamFailure("llm_bad_response")
        found = []
        for pos in range(start, len(self.content)):
            char = self.content[pos]
            if self.quoted:
                if self.escaped:
                    self.escaped = False
                elif char == "\\":
                    self.escaped = True
                elif char == '"':
                    self.quoted = False
                    if len(self.stack) == 1 and self.expect_key:
                        try:
                            self.key = strict_json(self.content[self.string_start:pos + 1])
                        except ValueError:
                            self.key = None
                        self.expect_key = False
                continue
            if char == '"':
                self.quoted, self.string_start = True, pos
            elif char in "[{":
                tag = None
                if len(self.stack) == 1:
                    if self.key == "items" and char == "[":
                        tag = "items"
                    elif self.key == "reference" and char == "{":
                        tag = "reference"
                elif len(self.stack) == 2 and self.stack[-1][1] == "items" and char == "{":
                    tag = "item"
                self.stack.append((char, tag, pos))
            elif char in "]}" and self.stack:
                opening, tag, obj_start = self.stack.pop()
                if (opening, char) not in (("{", "}"), ("[", "]")):
                    raise StreamFailure("llm_bad_response")
                if tag in ("item", "reference"):
                    ordinal = self.ordinal
                    if tag == "item":
                        self.ordinal += 1
                    found.append((tag, ordinal, self.content[obj_start:pos + 1]))
            elif char == "," and len(self.stack) == 1:
                self.key, self.expect_key = None, True
        return found
