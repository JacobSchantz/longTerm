import sys
import json
from transformers import pipeline

# Read input from command line arguments
if len(sys.argv) < 3:
    print("Error: Missing arguments. Usage: script.py <text> <activityDescription>", file=sys.stderr)
    sys.exit(1)

text = sys.argv[1]
activity_description = sys.argv[2]

# Load a local language model (example with a small model for text classification or generation)
# Replace 'distilbert-base-uncased' with a model suitable for your task
model = pipeline('text-classification', model='distilbert-base-uncased', tokenizer='distilbert-base-uncased')

# Simple logic to determine if on task (this is a placeholder, adjust based on your model and logic)
# In a real scenario, you might use a generative model to produce a response
input_text = f"Screen text: {text} Intended task: {activity_description}"
result = model(input_text)

# Placeholder logic for demonstration
# In practice, you would parse the model's output to determine 'on task' or 'off task'
label = result[0]['label']
score = result[0]['score']
response = "on task" if score > 0.5 else "off task"

# Output the result
print(response)
