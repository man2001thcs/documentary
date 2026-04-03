package com.prompt.example.gemini.websocket;

import java.text.SimpleDateFormat;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.SendTo;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.prompt.example.gemini.model.GeminiChatModel;
import com.prompt.example.gemini.model.GeminiWsChatModel;
import com.prompt.example.gemini.service.GeminiPromptService;
import org.springframework.web.bind.annotation.RequestBody;

@Controller
public class GeminiPromptSocket {

      @Autowired
      private GeminiPromptService geminiPromptService;

      @MessageMapping("/ws/chat")
      @SendTo("/topic/messages")
      public void send(GeminiWsChatModel chatModel) throws Exception {
            geminiPromptService.chatWithTechWs(
                  chatModel.getSessionId(),
                  chatModel.getText()
              );
      }

}
