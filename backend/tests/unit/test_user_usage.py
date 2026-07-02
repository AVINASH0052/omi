"""Unit tests for get_monthly_chat_usage — the freemium chat-question quota source.

Regression coverage for the nested-vs-flat bug: the Rust desktop-backend commits
desktop_chat usage via dotted Firestore fieldPaths, which Firestore materializes as a
NESTED map ({desktop_chat: {call_count, ...}}), whereas the Python backend writes flat
dotted keys ("chat.<model>.call_count"). The reader must count desktop
`quota_questions` rather than internal generation `call_count`, count backend chat,
and exclude company-driven keys (conv_*, memories.*).
"""

from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest

from database import user_usage


@pytest.fixture
def mock_db(monkeypatch):
    db = MagicMock(name="db")
    monkeypatch.setattr(user_usage, "db", db)
    return db


class _Snap:
    def __init__(self, data):
        self._d = data
        self.exists = True

    def to_dict(self):
        return self._d


class _DocRef:
    def __init__(self, doc_id, data):
        self.id = doc_id
        self._data = data

    def get(self):
        return _Snap(self._data)


def _setup_docs(mock_db, docs):
    refs = [_DocRef(k, v) for k, v in docs.items()]
    llm_usage_ref = MagicMock()
    llm_usage_ref.list_documents.return_value = refs
    mock_db.collection.return_value.document.return_value.collection.return_value = llm_usage_ref


NOW = datetime(2026, 6, 23, tzinfo=timezone.utc)


def test_counts_nested_desktop_quota_questions_plus_flat_backend_chat(mock_db):
    _setup_docs(
        mock_db,
        {
            "2026-06-23": {
                "desktop_chat": {
                    "call_count": 5,  # internal generations — must NOT count as questions
                    "quota_questions": 2,  # visible user turns — counted
                    "cost_usd": 1.5,
                },
                "desktop_chat_omi": {"call_count": 3},
                "desktop_chat_realtime": {"call_count": 2},
                "chat.gpt-4.call_count": 4,  # flat backend chat — counted
                "conv_apps.gpt-5.call_count": 100,  # proactive/processing — excluded
                "memories.gpt-4.call_count": 50,  # excluded
                "date": "2026-06-23",
            },
            "2026-05-30": {"desktop_chat": {"quota_questions": 999}},  # other month — excluded
        },
    )
    r = user_usage.get_monthly_chat_usage("uid", now=NOW)
    # 2 (desktop quota questions) + 2 (legacy realtime turns) + 4 (flat chat.*);
    # internal generations + proactive excluded.
    assert r["questions"] == 8, r
    assert r["cost_usd"] == 1.5, r


def test_backend_quota_questions_supersede_legacy_chat_call_count(mock_db):
    _setup_docs(
        mock_db,
        {
            "2026-06-23": {
                "backend_chat": {"quota_questions": 3},
                "chat.gpt-4.call_count": 9,  # legacy LLM telemetry — ignored when explicit counter exists
                "date": "2026-06-23",
            },
            "2026-06-24": {
                "backend_chat.quota_questions": 2,
                "chat.gpt-4.call_count": 8,
                "date": "2026-06-24",
            },
        },
    )
    r = user_usage.get_monthly_chat_usage("uid", now=NOW)
    assert r["questions"] == 5, r


def test_realtime_usage_cost_does_not_count_internal_generations_as_questions(mock_db):
    _setup_docs(
        mock_db,
        {
            "2026-06-10": {
                "desktop_chat": {"call_count": 7, "quota_questions": 0, "cost_usd": 0.4},
                "desktop_chat_realtime": {"call_count": 7, "quota_questions": 0},
            }
        },
    )
    r = user_usage.get_monthly_chat_usage("uid", now=NOW)
    assert r["questions"] == 0
    assert r["cost_usd"] == 0.4


def test_realtime_quota_breakdown_prevents_legacy_call_count_double_count(mock_db):
    _setup_docs(
        mock_db,
        {
            "2026-06-10": {
                "desktop_chat": {"call_count": 10, "quota_questions": 4, "cost_usd": 0.4},
                "desktop_chat_realtime": {"call_count": 3, "quota_questions": 3},
            },
            "2026-06-11": {
                "desktop_chat.quota_questions": 2,
                "desktop_chat_realtime.call_count": 5,
                "desktop_chat_realtime.quota_questions": 5,
                "desktop_chat.cost_usd": 0.2,
            },
        },
    )
    r = user_usage.get_monthly_chat_usage("uid", now=NOW)
    assert r["questions"] == 6
    assert r["cost_usd"] == 0.6


def test_desktop_helper_only_call_count_does_not_count_as_questions(mock_db):
    _setup_docs(
        mock_db,
        {
            "2026-06-10": {
                "desktop_chat": {"call_count": 7, "cost_usd": 0.4},
                "desktop_chat_omi": {"call_count": 7},
            }
        },
    )
    r = user_usage.get_monthly_chat_usage("uid", now=NOW)
    assert r["questions"] == 0
    assert r["cost_usd"] == 0.4


def test_legacy_realtime_call_count_fallback_uses_realtime_breakdown_only(mock_db):
    _setup_docs(
        mock_db,
        {
            "2026-06-10": {
                "desktop_chat.call_count": 7,
                "desktop_chat_realtime.call_count": 7,
                "desktop_chat.cost_usd": 0.4,
            }
        },
    )
    r = user_usage.get_monthly_chat_usage("uid", now=NOW)
    assert r["questions"] == 7
    assert r["cost_usd"] == 0.4


def test_only_proactive_counts_zero(mock_db):
    _setup_docs(mock_db, {"2026-06-23": {"conv_apps.gpt-5.call_count": 100, "memories.gpt-4.call_count": 50}})
    assert user_usage.get_monthly_chat_usage("uid", now=NOW)["questions"] == 0
