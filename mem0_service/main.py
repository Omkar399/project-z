#!/usr/bin/env python3
"""
Mem0 Service - Long-term memory for ProjectZ
Provides REST API for storing and retrieving memories using Mem0
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Dict, Optional
import uvicorn
from mem0 import Memory
import logging
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="ProjectZ Mem0 Service",
    description="Long-term memory service for ProjectZ AI assistant",
    version="1.0.0"
)

# CORS middleware for local development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Get OpenAI API key from environment
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
if not OPENAI_API_KEY:
    raise ValueError("OPENAI_API_KEY not found in environment variables")

config = {
    "vector_store": {
        "provider": "qdrant",
        "config": {
            "collection_name": "clippy_memories",
            "path": "./data/qdrant",
        }
    },
    "embedder": {
        "provider": "openai",
        "config": {
            "model": "text-embedding-3-small"
        }
    },
    "llm": {
        "provider": "openai",
        "config": {
            "model": "gpt-4o-mini",
            "temperature": 0.1,
            "max_tokens": 2000
        }
    },
    "version": "v1.1"
}

try:
    memory = Memory.from_config(config)
    logger.info("✅ Mem0 initialized successfully with OpenAI embeddings")
except Exception as e:
    logger.error(f"❌ Failed to initialize Mem0: {e}")
    logger.error(f"   Make sure OpenAI API key is valid and mem0ai package is installed")
    memory = None

# Pydantic models
class Message(BaseModel):
    role: str
    content: str

class AddMemoryRequest(BaseModel):
    messages: List[Message]
    user_id: str = "default_user"
    metadata: Optional[Dict] = None

class SearchMemoryRequest(BaseModel):
    query: str
    user_id: str = "default_user"
    limit: int = 5

class MemoryResponse(BaseModel):
    id: str
    memory: str
    user_id: str
    created_at: Optional[str] = None
    updated_at: Optional[str] = None

# API Endpoints
@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "service": "ProjectZ Mem0 Service",
        "status": "running" if memory else "error",
        "version": "1.0.0"
    }

@app.get("/health")
async def health():
    """Health check"""
    if not memory:
        raise HTTPException(status_code=503, detail="Mem0 not initialized")
    return {"status": "healthy"}

@app.post("/add")
async def add_memory(request: AddMemoryRequest):
    """
    Add memories from a conversation
    Mem0 will automatically extract important facts
    """
    if not memory:
        raise HTTPException(status_code=503, detail="Mem0 not initialized")
    
    try:
        # Convert messages to Mem0 format
        messages_list = [
            {"role": msg.role, "content": msg.content}
            for msg in request.messages
        ]
        
        logger.info(f"💾 Adding memories for user: {request.user_id}")
        
        # Add to Mem0 - it will extract memories automatically
        result = memory.add(
            messages=messages_list,
            user_id=request.user_id,
            metadata=request.metadata or {}
        )
        
        logger.info(f"✅ Memories added: {result}")
        
        return {
            "success": True,
            "result": result,
            "message": "Memories extracted and stored"
        }
    except Exception as e:
        logger.error(f"❌ Error adding memory: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/search")
async def search_memories(request: SearchMemoryRequest):
    """
    Search for relevant memories
    Returns memories that match the query semantically
    """
    if not memory:
        raise HTTPException(status_code=503, detail="Mem0 not initialized")
    
    try:
        logger.info(f"🔍 Searching memories for: {request.query}")
        
        # Search Mem0
        results = memory.search(
            query=request.query,
            user_id=request.user_id,
            limit=request.limit
        )
        
        # Mem0 search returns {'results': [...]}
        memories = []
        if results:
            # Handle dict format with 'results' key
            if isinstance(results, dict) and 'results' in results:
                result_list = results['results']
            else:
                result_list = results if isinstance(results, list) else []
            
            for result in result_list:
                memories.append({
                    "id": str(result.get("id", "")),
                    "memory": str(result.get("memory", "")),
                    "score": float(result.get("score", 0.0)),
                    "metadata": result.get("metadata", {})
                })
        
        logger.info(f"✅ Found {len(memories)} formatted memories")
        
        return {
            "success": True,
            "count": len(memories),
            "memories": memories
        }
    except Exception as e:
        logger.error(f"❌ Error searching memories: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/all")
async def get_all_memories(user_id: str = "default_user"):
    """
    Get all stored memories for a user
    """
    if not memory:
        raise HTTPException(status_code=503, detail="Mem0 not initialized")
    
    try:
        logger.info(f"📋 Getting all memories for user: {user_id}")
        
        # Get all memories
        results = memory.get_all(user_id=user_id)
        
        # Mem0 get_all returns {'results': [...]}
        memories = []
        if results:
            if isinstance(results, dict) and 'results' in results:
                result_list = results['results']
            else:
                result_list = results if isinstance(results, list) else []
            
            for result in result_list:
                memories.append({
                    "id": str(result.get("id", "")),
                    "memory": str(result.get("memory", "")),
                    "metadata": result.get("metadata", {})
                })
        
        logger.info(f"✅ Found {len(memories)} total memories")
        
        return {
            "success": True,
            "count": len(memories),
            "memories": memories
        }
    except Exception as e:
        logger.error(f"❌ Error getting memories: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/clear")
async def clear_memories(user_id: str = "default_user"):
    """
    Clear all memories for a user
    """
    if not memory:
        raise HTTPException(status_code=503, detail="Mem0 not initialized")
    
    try:
        logger.info(f"🗑️ Clearing all memories for user: {user_id}")
        
        # Delete all memories for user
        memory.delete_all(user_id=user_id)
        
        logger.info(f"✅ All memories cleared")
        
        return {
            "success": True,
            "message": "All memories cleared"
        }
    except Exception as e:
        logger.error(f"❌ Error clearing memories: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    logger.info("🚀 Starting Mem0 Service on http://localhost:8420")
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8420,
        log_level="info"
    )

