package com.prompt.example.gemini;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication(exclude = { 
	org.springframework.ai.model.vertexai.autoconfigure.gemini.VertexAiGeminiChatAutoConfiguration.class 
  })
public class GeminiApplication {

	public static void main(String[] args) {
		SpringApplication.run(GeminiApplication.class, args);
	}

}
