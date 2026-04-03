package com.prompt.example.gemini.controller;

import java.text.SimpleDateFormat;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.SendTo;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.prompt.example.gemini.model.GeminiChatModel;
import com.prompt.example.gemini.model.GeminiWsChatModel;
import com.prompt.example.gemini.service.GeminiPromptService;
import org.springframework.web.bind.annotation.RequestBody;

@RestController
@RequestMapping("/api/gemini/prompt")
public class GeminiPromptController {

      @Autowired
      private GeminiPromptService geminiPromptService;

      @PostMapping("/get-parts")
      public ResponseEntity<?> getParts(@RequestParam int money, @RequestParam String profile) {
            return ResponseEntity.ok(geminiPromptService.getPCRecommendation(money, profile));
      }

      @PostMapping("/post/chat")
      public ResponseEntity<?> chat(@RequestParam String sessionId, @RequestBody GeminiChatModel chatModel) {
            // TODO: process POST request

            return ResponseEntity.ok(geminiPromptService.chatWithTech(sessionId, chatModel.getText()));
      }
}
