package com.prompt.example.gemini.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@AllArgsConstructor
@NoArgsConstructor
@Data
public class GeminiWsChatModel {
      private String sessionId;
      private String text;
      
}
