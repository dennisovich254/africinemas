"""One live call to the AI agent's model (P8.1's manual smoke test).

    jac run scripts/llm_smoke.jac

Uses the agent's model (gemini/gemini-3.5-flash-lite unless AFRICINEMAS_LLM_MODEL says
otherwise) with the key from the environment (GEMINI_API_KEY). It calls the model
without the agent's fallback, so a missing or wrong key shows as the provider's error
rather than the polite "can't answer right now". No tools, no cinema data, no customer
data: one short question.
"""

import core.agent.agent as agent;

def smoke(question: str) -> str by agent.agent_model();
sem smoke = "Answer in one short sentence.";
sem smoke.question = "A simple question.";

with entry {
    print("model:", getattr(agent.agent_model, "model_name", "?"));
    print("reply:", smoke("Which planet is known as the red planet?"));
}
