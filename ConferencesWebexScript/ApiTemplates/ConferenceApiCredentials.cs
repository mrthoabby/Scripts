using ConferencesWebexScript.Helpers;

namespace ConferencesWebexScript.ApiTemplates
{
    internal class ConferenceApiCredentials
    {
        public string Event { get; set; }
        public string AuToken => ScriptConfigurationHelper._auToken;
        public string IntegrationId => ScriptConfigurationHelper._integrationId;
    }
}
