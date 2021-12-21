namespace ConferencesWebexScript.ApiTemplates
{
    public class ConferenceResponseRecording
    {
        public bool locked { get; set; }
        public bool recordingStarted { get; set; }
        public bool recordingPaused { get; set; }
        public string message { get; set; }
    }
}
