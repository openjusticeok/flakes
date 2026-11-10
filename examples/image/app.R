# A deliberately small Shiny app: what this example demonstrates is the image,
# not the dashboard. Note that it reads its port from the environment, because a
# container host decides the port — hard-coding 3838 is the most common way a
# working app fails on Cloud Run.
library(shiny)
library(bslib)

ui <- page_sidebar(
  title = "opi image example",
  sidebar = sidebar(
    sliderInput("n", "Draws", min = 10, max = 500, value = 100)
  ),
  card(
    card_header("R version in this container"),
    verbatimTextOutput("version")
  ),
  plotOutput("hist")
)

server <- function(input, output, session) {
  output$version <- renderText(R.version.string)
  output$hist <- renderPlot(hist(rnorm(input$n), main = "", xlab = ""))
}

shinyApp(ui, server)
