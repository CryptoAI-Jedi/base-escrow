"""
AI-assisted dispute assessment using Claude.

Non-blocking: if the call fails for any reason, the resolver continues with
the deterministic decision unchanged. The AI layer is purely advisory.
"""
import json
import os
from typing import Optional


def assess_dispute(
    escrow_id: str,
    status: str,
    buyer: str,
    seller: str,
    action: str,
    reason_code: str,
) -> Optional[dict]:
    """
    Call Claude to assess the escrow dispute and return structured analysis.

    The returned dict is metadata only — it never changes the action or
    should_submit_tx fields returned by the policy engine.

    Returns None if ANTHROPIC_API_KEY is not set or if the call fails.
    """
    api_key = os.getenv("ANTHROPIC_API_KEY", "")
    if not api_key:
        return None

    try:
        import anthropic

        client = anthropic.Anthropic(api_key=api_key)

        prompt = (
            "You are an escrow dispute assessor. You will be given the current "
            "state of an on-chain escrow contract and the deterministic policy "
            "decision that has already been made. Your job is to assess the "
            "situation and confirm whether the policy outcome is appropriate.\n\n"
            f"Escrow state:\n"
            f"  Contract: {escrow_id}\n"
            f"  Status: {status}\n"
            f"  Buyer: {buyer}\n"
            f"  Seller: {seller}\n"
            f"  Policy decision: {action} (reason: {reason_code})\n\n"
            "Return a JSON object with exactly these three fields:\n"
            '  "classification": a short snake_case label for the dispute type '
            '(e.g. "unresolved_buyer_seller_dispute", "funded_timeout_release")\n'
            '  "policy_alignment": either "confirmed" if the policy outcome is '
            'appropriate for this state, or "uncertain" if the state is ambiguous\n'
            '  "rationale": 1-2 sentences describing the escrow situation and why '
            "the policy outcome is or is not appropriate\n\n"
            "Return only the JSON object. No explanation, no markdown, no extra text."
        )

        message = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=256,
            messages=[{"role": "user", "content": prompt}],
        )

        raw = message.content[0].text.strip()
        assessment = json.loads(raw)

        required_keys = {"classification", "policy_alignment", "rationale"}
        if not required_keys.issubset(assessment.keys()):
            print(f"[AI] Unexpected response shape, skipping: {assessment}")
            return None

        return assessment

    except Exception as e:
        print(f"[AI] Assessment failed (non-fatal): {e}")
        return None
