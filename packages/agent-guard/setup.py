from setuptools import setup, find_packages

setup(
    name="agent-guard",
    version="0.1.0",
    description="Enterprise-grade AI agent quality gates and context lifecycle governance",
    author="AI Collaboration Framework Contributors",
    license="Apache-2.0",
    python_requires=">=3.10",
    packages=find_packages(),
    entry_points={
        "console_scripts": [
            "agent-guard=agent_guard.cli:main",
        ],
    },
)
