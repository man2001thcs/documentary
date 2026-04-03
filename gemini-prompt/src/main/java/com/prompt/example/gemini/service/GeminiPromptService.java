package com.prompt.example.gemini.service;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.common.collect.ImmutableList;
import com.google.genai.Chat;
import com.google.genai.Client;
import com.google.genai.ResponseStream;
import com.google.genai.types.GenerateContentConfig;
import com.google.genai.types.GenerateContentResponse;
import com.google.genai.types.GoogleSearch;
import com.google.genai.types.HarmBlockThreshold;
import com.google.genai.types.HarmCategory;
import com.google.genai.types.Part;
import com.google.genai.types.SafetySetting;
import com.google.genai.types.Schema;
import com.google.genai.types.Tool;
import com.google.genai.types.Type;
import com.prompt.example.gemini.model.GeminiWsChatModel;
import com.google.genai.types.ActivityHandling.Known;

import lombok.extern.slf4j.Slf4j;

import com.google.genai.types.Content;

import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;

@Slf4j
@Service
public class GeminiPromptService {

      private final Client client;
      private final String MODEL = "gemini-2.5-flash-lite";
      public static final String CHAT_SESSION = "AVADA"; // Or "gemini-1.5-flash"
      @Value("${gemini.apikey}")
      private String apikey;
      @Autowired
      private RedisTemplate<String, Object> redisTemplate;

      @Autowired
      private SimpMessagingTemplate messagingTemplate;

      private static final String SYSTEM_INSTRUCTION = "You are a professional PC hardware technician with 20 years of experience. "
                  +
                  "Your priority is ALWAYS price-to-performance. You provide blunt, expert advice. " +
                  "You hate 'RGB tax' and overspending on aesthetics. You know every socket, chipset, and bottleneck. "
                  +
                  "When recommending parts, explain WHY they are the best value. " +
                  "Keep your tone professional, slightly grizzled, but helpful.";

      // Sets the safety settings in the config.
      ImmutableList<SafetySetting> safetySettings = ImmutableList.of(
                  SafetySetting.builder()
                              .category(HarmCategory.Known.HARM_CATEGORY_HATE_SPEECH)
                              .threshold(HarmBlockThreshold.Known.BLOCK_ONLY_HIGH)
                              .build(),
                  SafetySetting.builder()
                              .category(HarmCategory.Known.HARM_CATEGORY_DANGEROUS_CONTENT)
                              .threshold(HarmBlockThreshold.Known.BLOCK_LOW_AND_ABOVE)
                              .build());

      private static final Map<String, Chat> chatStore = new ConcurrentHashMap<>();

      public GeminiPromptService(@Value("${gemini.project}") String project, @Value("${gemini.apikey}") String apikey) {
            // The new SDK can also pick up GEMINI_API_KEY from env automatically
            this.client = Client.builder()
                        .apiKey(apikey)
                        // .project(null)
                        // .location(null)
                        .build();
      }

      public String getPCRecommendation(int budget, String useCase) {
            // Define Response Schema for structured JSON
            Map<String, Schema> itemJsonMap = new HashMap<>();
            itemJsonMap.put("name", Schema.builder().type(Type.Known.STRING).build());
            itemJsonMap.put("publisher", Schema.builder().type(Type.Known.STRING).build());
            itemJsonMap.put("category", Schema.builder().type(Type.Known.STRING).build());
            itemJsonMap.put("price", Schema.builder().type(Type.Known.NUMBER).build());
            itemJsonMap.put("performanceScore", Schema.builder().type(Type.Known.NUMBER).build());
            itemJsonMap.put("description", Schema.builder().type(Type.Known.STRING).build());

            Schema partsSchema = Schema.builder()
                        .type(Type.Known.OBJECT)
                        .properties(itemJsonMap)
                        .required(List.of("name", "publisher", "category", "price", "performanceScore",
                                    "description"))
                        .build();

            Map<String, Schema> schemaJsonMap = new HashMap<>();
            schemaJsonMap.put("parts", Schema.builder()
                        .type(Type.Known.ARRAY)
                        .items(partsSchema)
                        .build());
            schemaJsonMap.put("techNotes", Schema.builder().type(Type.Known.STRING).build());

            Schema rootSchema = Schema.builder()
                        .type(Type.Known.OBJECT)
                        .properties(schemaJsonMap)
                        .required(List.of("parts", "techNotes"))
                        .build();

            Content systemInstruction = Content.fromParts(Part.fromText(SYSTEM_INSTRUCTION));
            Tool googleSearchTool = Tool.builder().googleSearch(GoogleSearch.builder()).build();

            GenerateContentConfig config = GenerateContentConfig.builder()
                        .systemInstruction(systemInstruction)
                        .safetySettings(safetySettings)
                        .responseSchema(rootSchema)
                        .responseMimeType("application/json")
                        // .tools(googleSearchTool)
                        .build();

            String prompt = String.format(
                        "Recommend a PC build for $%d focused on %s. Prioritize price-to-performance.", budget,
                        useCase);

            GenerateContentResponse response = client.models.generateContent(MODEL, prompt, config);
            return response.text();
      }

      public String troubleshootIssue(String issue) {
            Content systemInstruction = Content.fromParts(Part.fromText(SYSTEM_INSTRUCTION));

            GenerateContentConfig config = GenerateContentConfig.builder()
                        .systemInstruction(systemInstruction)
                        .build();

            String prompt = "Troubleshoot this PC issue: \"" + issue + "\". Provide a step-by-step diagnostic guide.";

            return client.models.generateContent(MODEL, prompt, config).text();
      }

      public String chatWithTech(String sessionId, String message) {
            String key = CHAT_SESSION + "::id=" + sessionId;
            ObjectMapper mapper = new ObjectMapper();
            mapper.registerModule(new com.fasterxml.jackson.datatype.jdk8.Jdk8Module());
            // CRITICAL: Prevent Jackson from writing "null" for Optional fields
            mapper.setDefaultPropertyInclusion(
                        JsonInclude.Value.construct(JsonInclude.Include.NON_NULL, JsonInclude.Include.ALWAYS));

            // Prevent crashing if the SDK adds new fields in future updates
            mapper.configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
            // 1. Get from Redis as a String
            String cachedJson = (String) redisTemplate.opsForValue().get(key);
            List<Content> historyContent = new ArrayList<>();

            if (cachedJson != null) {
                  try {
                        // 2. Deserialize JSON string back to List<Content>
                        List<Map<String, Object>> rawHistory = mapper.readValue(
                                    cachedJson,
                                    new TypeReference<List<Map<String, Object>>>() {
                                    });

                        // 2. MANUALLY rebuild Content objects (skipping null fields)
                        for (Map<String, Object> entry : rawHistory) {
                              String role = (String) entry.get("role");
                              List<Map<String, String>> parts = (List<Map<String, String>>) entry.get("parts");

                              List<Part> validParts = new ArrayList<>();
                              for (Map<String, String> p : parts) {
                                    if (p.containsKey("text") && p.get("text") != null) {
                                          validParts.add(Part.fromText(p.get("text")));
                                    }
                              }
                              historyContent.add(Content.builder().role(role).parts(validParts).build());
                        }
                  } catch (Exception e) {
                        log.error("Failed to parse history from Redis", e);
                  }
            }

            // The new SDK uses a unified Chat interface
            Content systemInstruction = Content.fromParts(Part.fromText(SYSTEM_INSTRUCTION));

            GenerateContentConfig config = GenerateContentConfig.builder()
                        .systemInstruction(systemInstruction)
                        .safetySettings(safetySettings)

                        .build();

            // 3. Add the new message to history
            historyContent.add(Content.builder().role("user").parts(Collections.singletonList(Part.fromText(message)))
                        .build());

            ResponseStream<GenerateContentResponse> responseStream = client.models.generateContentStream(MODEL,
                        historyContent,
                        config);

            StringBuilder buildResponse = new StringBuilder();
            System.out.println("Streaming response:");
            for (GenerateContentResponse response : responseStream) {
                  // Iterate over the stream and print each response as it arrives.
                  System.out.print(response.text());
                  buildResponse.append(response.text());
            }

            historyContent.add(Content.builder().role("model")
                        .parts(Collections.singletonList(Part.fromText(buildResponse.toString()))).build());

            try {
                  String updatedJson = mapper.writeValueAsString(historyContent);
                  redisTemplate.opsForValue().set(key, updatedJson, Duration.ofHours(1));
            } catch (Exception e) {
                  log.error("Failed to save history to Redis", e);
            }

            return buildResponse.toString();
      }

      public void chatWithTechWs(String sessionId, String message) {
            String key = CHAT_SESSION + "::id=" + sessionId;
            ObjectMapper mapper = new ObjectMapper();
            mapper.registerModule(new com.fasterxml.jackson.datatype.jdk8.Jdk8Module());
            // CRITICAL: Prevent Jackson from writing "null" for Optional fields
            mapper.setDefaultPropertyInclusion(
                        JsonInclude.Value.construct(JsonInclude.Include.NON_NULL, JsonInclude.Include.ALWAYS));

            // Prevent crashing if the SDK adds new fields in future updates
            mapper.configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
            // 1. Get from Redis as a String
            String cachedJson = (String) redisTemplate.opsForValue().get(key);
            List<Content> historyContent = new ArrayList<>();

            if (cachedJson != null) {
                  try {
                        // 2. Deserialize JSON string back to List<Content>
                        List<Map<String, Object>> rawHistory = mapper.readValue(
                                    cachedJson,
                                    new TypeReference<List<Map<String, Object>>>() {
                                    });

                        // 2. MANUALLY rebuild Content objects (skipping null fields)
                        for (Map<String, Object> entry : rawHistory) {
                              String role = (String) entry.get("role");
                              List<Map<String, String>> parts = (List<Map<String, String>>) entry.get("parts");

                              List<Part> validParts = new ArrayList<>();
                              for (Map<String, String> p : parts) {
                                    if (p.containsKey("text") && p.get("text") != null) {
                                          validParts.add(Part.fromText(p.get("text")));
                                    }
                              }
                              historyContent.add(Content.builder().role(role).parts(validParts).build());
                        }
                  } catch (Exception e) {
                        log.error("Failed to parse history from Redis", e);
                  }
            }

            // The new SDK uses a unified Chat interface
            Content systemInstruction = Content.fromParts(Part.fromText(SYSTEM_INSTRUCTION));

            GenerateContentConfig config = GenerateContentConfig.builder()
                        .systemInstruction(systemInstruction)
                        .safetySettings(safetySettings)

                        .build();

            // 3. Add the new message to history
            historyContent.add(Content.builder().role("user").parts(Collections.singletonList(Part.fromText(message)))
                        .build());

            ResponseStream<GenerateContentResponse> responseStream = client.models.generateContentStream(MODEL,
                        historyContent,
                        config);

            System.out.println("Streaming response:");

            StringBuilder fullResponse = new StringBuilder();

            for (GenerateContentResponse response : responseStream) {
                  String chunk = response.text();

                  if (chunk != null && !chunk.isEmpty()) {

                        log.info(chunk);

                        fullResponse.append(chunk);

                        // send partial chunk
                        messagingTemplate.convertAndSend(
                                    "/topic/messages",
                                    new GeminiWsChatModel(sessionId, chunk) // send chunk only
                        );
                  }
            }

            // ✅ send END signal (important for UI)
            messagingTemplate.convertAndSend(
                        "/topic/messages",
                        new GeminiWsChatModel(sessionId, "[END]"));

            historyContent.add(Content.builder().role("model")
                        .parts(Collections.singletonList(Part.fromText(fullResponse.toString()))).build());

            try {
                  String updatedJson = mapper.writeValueAsString(historyContent);
                  redisTemplate.opsForValue().set(key, updatedJson, Duration.ofHours(1));
            } catch (Exception e) {
                  log.error("Failed to save history to Redis", e);
            }
      }
}