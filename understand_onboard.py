#!/usr/bin/env python3
"""
understand_onboard.py — HCM_RODS Codebase Onboarding Tool

Uses the Claude API to help developers understand the HCM_RODS Oracle PL/SQL
ETL codebase. Supports interactive Q&A, file-specific analysis, and full
onboarding guide generation.

Usage:
    python understand_onboard.py                         # interactive mode
    python understand_onboard.py "What does X do?"       # one-shot question
    python understand_onboard.py --file <filename.sql>   # explain a file
    python understand_onboard.py --onboard               # full onboarding guide
"""

import anthropic
import argparse
import os
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

MODEL = "claude-opus-4-6"
REPO_ROOT = Path(__file__).parent

# Files to include in the codebase context (ordered by importance)
CODEBASE_FILES = [
    "README.md",
    "How to Execute",
    "pkg_spectra_worker_etl_v4_pkg.sql",        # ETL package spec
    "pkg_spectra_worker_etl_v4_pkB.sql",         # ETL package body
    "XX_BOSS_PARALLEL_RUNNER_PKG.SQL.sql",       # Parallel runner spec
    "XX_BOSS_PARALLEL_RUNNER_PKB.SQL.sql",       # Parallel runner body
    "xx_boss_query_builder_pkg.sql",             # Query builder spec
    "xx_boss_query_builder_pkB.sql",             # Query builder body
    "batch_api_call_with_apex_cred_prc.sql",     # API call procedure
    "LOG_ERROR_PRC.sql",                         # Error logging
    "XX_INT_SAAS_EXTRACT_CONFIG_DDL.sql",        # Config table DDL
    "xx_int_extract_job_log_ddl1.sql",           # Job log table DDL
    "XX_RODS_GRANTS.sql",                        # DB grants
    "get_exception_name.sql",                    # Utility
    "paygroup_tree_diagram.md",                  # PayGroup schema docs
]

SYSTEM_PROMPT = """\
You are an expert Oracle PL/SQL developer and technical mentor helping a new
developer onboard to the HCM_RODS codebase — an Oracle PL/SQL ETL framework
that extracts Human Capital Management (HCM) and Payroll data from Oracle Cloud
(BOSS API) into a read-only data store.

The codebase uses:
- Oracle PL/SQL packages (spec + body pattern)
- OAuth 2.0 for SaaS API authentication (via APEX_WEB_SERVICE / UTL_HTTP)
- JSON processing with Oracle JSON functions
- Parallel job execution via DBMS_SCHEDULER
- ZIP/BLOB handling for compressed API responses
- Complex nested XML/JSON schema (PayGroup has 103 containers, 12 levels deep)

When answering:
- Be concrete and cite specific procedure/function names when relevant
- Explain Oracle-specific patterns (e.g., BULK COLLECT, autonomous transactions)
- Use examples from the actual codebase when helpful
- For onboarding, build up understanding from high-level architecture to details
- Flag gotchas, common mistakes, and non-obvious design decisions
"""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def load_codebase() -> list[dict]:
    """Load all codebase files as a list of text blocks with cache_control."""
    blocks = []
    for fname in CODEBASE_FILES:
        path = REPO_ROOT / fname
        if not path.exists():
            continue
        try:
            content = path.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        blocks.append({
            "type": "text",
            "text": f"\n\n{'='*60}\n FILE: {fname}\n{'='*60}\n{content}",
        })

    if not blocks:
        return blocks

    # Mark the last block as cacheable so the full codebase context is cached
    # after the first request — subsequent questions reuse it at ~90% discount.
    blocks[-1]["cache_control"] = {"type": "ephemeral"}
    return blocks


def build_user_message(question: str, codebase_blocks: list[dict]) -> list[dict]:
    """Combine codebase context with the user's question."""
    return [
        {
            "type": "text",
            "text": "Here is the complete HCM_RODS codebase for context:",
        },
        *codebase_blocks,
        {
            "type": "text",
            "text": f"\n\nQuestion: {question}",
        },
    ]


def stream_response(client: anthropic.Anthropic, messages: list[dict]) -> str:
    """Stream Claude's response, printing tokens as they arrive."""
    full_text = ""
    with client.messages.stream(
        model=MODEL,
        max_tokens=8192,
        thinking={"type": "adaptive"},
        system=SYSTEM_PROMPT,
        messages=messages,
    ) as stream:
        in_thinking = False
        for event in stream:
            if event.type == "content_block_start":
                if event.content_block.type == "thinking":
                    print("\n\033[2m[Thinking...]\033[0m", flush=True)
                    in_thinking = True
                elif event.content_block.type == "text":
                    if in_thinking:
                        print()  # newline after thinking block
                    in_thinking = False
            elif event.type == "content_block_delta":
                if event.delta.type == "text_delta":
                    print(event.delta.text, end="", flush=True)
                    full_text += event.delta.text
    print()  # final newline
    return full_text


def explain_file(client: anthropic.Anthropic, filename: str) -> None:
    """Explain a specific file in depth."""
    path = REPO_ROOT / filename
    if not path.exists():
        # Try partial match
        matches = list(REPO_ROOT.glob(f"*{filename}*"))
        if not matches:
            print(f"Error: file not found: {filename}")
            sys.exit(1)
        path = matches[0]
        filename = path.name

    content = path.read_text(encoding="utf-8", errors="replace")
    question = (
        f"Please give a comprehensive explanation of `{filename}`:\n\n"
        "1. Purpose and responsibilities of this file/package\n"
        "2. Key procedures/functions and what they do\n"
        "3. Important data flows and dependencies\n"
        "4. Non-obvious design decisions or gotchas\n"
        "5. How it fits into the overall HCM_RODS architecture\n\n"
        f"File contents:\n```sql\n{content}\n```"
    )

    messages = [{"role": "user", "content": question}]
    print(f"\n\033[1mExplaining: {filename}\033[0m\n")
    stream_response(client, messages)


def generate_onboarding_guide(client: anthropic.Anthropic) -> None:
    """Generate a comprehensive onboarding guide for the whole codebase."""
    codebase_blocks = load_codebase()
    question = """\
Generate a comprehensive onboarding guide for a new developer joining the HCM_RODS project.
Structure it as follows:

## 1. Project Overview
What the system does and why it exists.

## 2. Architecture Overview
High-level diagram (text-based) of the components and data flow.

## 3. Key Concepts
Oracle PL/SQL patterns, OAuth flow, BOSS API, parallel execution — explained
simply for someone who may not be deeply familiar with Oracle.

## 4. Package Inventory
Brief description of every package/procedure and its role.

## 5. Data Flow Walkthrough
Step-by-step trace of what happens when `run_all_extracts_parallel` is called.

## 6. Configuration & Setup
What tables need to be populated, what grants are needed, how to configure environments.

## 7. PayGroup Schema
How to navigate the 103-container PayGroup XML structure.

## 8. Error Handling & Monitoring
How logging works, how to diagnose failures.

## 9. Common Tasks & Recipes
How to: add a new extract, debug a failed job, re-run a specific extract.

## 10. Gotchas & Non-Obvious Decisions
Things that will trip you up if you don't know them.
"""

    messages = [{"role": "user", "content": build_user_message(question, codebase_blocks)}]
    print("\n\033[1m=== HCM_RODS Developer Onboarding Guide ===\033[0m\n")
    stream_response(client, messages)


def interactive_mode(client: anthropic.Anthropic) -> None:
    """REPL-style interactive Q&A with codebase context cached across turns."""
    codebase_blocks = load_codebase()
    print("\033[1mHCM_RODS Onboarding Assistant\033[0m")
    print("Ask any question about the codebase. Type 'quit' or Ctrl-C to exit.\n")

    conversation: list[dict] = []

    while True:
        try:
            question = input("\033[1m> \033[0m").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nGoodbye!")
            break

        if not question:
            continue
        if question.lower() in {"quit", "exit", "q"}:
            print("Goodbye!")
            break

        # First turn: include full codebase context (cached after first call)
        if not conversation:
            user_content = build_user_message(question, codebase_blocks)
        else:
            user_content = question  # subsequent turns: just the question

        conversation.append({"role": "user", "content": user_content})
        print()
        answer = stream_response(client, conversation)
        conversation.append({"role": "assistant", "content": answer})
        print()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="HCM_RODS Codebase Onboarding Tool (powered by Claude)",
    )
    parser.add_argument(
        "question",
        nargs="?",
        help="One-shot question about the codebase",
    )
    parser.add_argument(
        "--file", "-f",
        metavar="FILENAME",
        help="Explain a specific file in depth",
    )
    parser.add_argument(
        "--onboard", "-o",
        action="store_true",
        help="Generate a full onboarding guide",
    )

    args = parser.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("Error: ANTHROPIC_API_KEY environment variable not set.", file=sys.stderr)
        sys.exit(1)

    client = anthropic.Anthropic(api_key=api_key)

    if args.file:
        explain_file(client, args.file)
    elif args.onboard:
        generate_onboarding_guide(client)
    elif args.question:
        codebase_blocks = load_codebase()
        messages = [{"role": "user", "content": build_user_message(args.question, codebase_blocks)}]
        print()
        stream_response(client, messages)
    else:
        interactive_mode(client)


if __name__ == "__main__":
    main()
